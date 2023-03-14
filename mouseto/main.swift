import Foundation
import ScreenCaptureKit
import Vision

// I've found that if the process gets interrupted partway through,
// ScreenCaptureKit gets wedged and requires a reboot to recover from.
// It's obnoxious to block a bunch of signals, but it's even
// more obnoxious to need to reboot just because serenade got distracted by something shiny.
// TODO: revisit this, as it seems like a macOS bug that will hopefully get fixed someday.
signal(SIGPIPE, SIG_IGN)
signal(SIGSTOP, SIG_IGN)
signal(SIGHUP, SIG_IGN)
signal(SIGINT, SIG_IGN)

let req = CommandLine.arguments.suffix(from: 1).joined(separator: " ")
let m: MouseTo = MouseTo(req)
// We need to integrate with the main runloop,
// in case the OS needs to show UI to get permission
// to get screen captures, move the mouse, etc.
DispatchQueue.main.async { m.run() }
dispatchMain()

class MouseTo: NSObject, SCStreamDelegate, SCStreamOutput {

  private let videoSampleBufferQueue = DispatchQueue(
    label: "xyz.commaok.mouseto.VideoSampleBufferQueue"
  )

  private var size: CGSize = CGSize()
  private var request: String = ""
  private var near: String?
  private var stream: SCStream?
  private var start: ContinuousClock.Instant = ContinuousClock.now

  init(_ req: String) {
    super.init()
    self.parseRequest(req)
  }

  func parseRequest(_ s: String) {
    guard let range = s.range(of: " near ", options: .caseInsensitive) else {
      self.request = s
      return
    }
    self.request = String(s.prefix(upTo: range.lowerBound))  // s.substring(to: range.lowerBound)
    self.near = String(s.suffix(from: range.upperBound))  // s.substring(from: range.upperBound)
    if self.near == "" {
      self.near = nil
    }
  }

  func error(_ msg: String) {
    print("ERROR: \(msg)")
    exit(1)
  }

  func time(_ msg: String) {
    let elapsed = ContinuousClock.now-self.start
    let ms = 1000 * elapsed.components.seconds + elapsed.components.attoseconds / Int64(1e15)
    print("[\(ms)ms] \(msg)")
  }

  func run() {
    self.getShareableContent()
  }

  func getShareableContent() {
    time("get shareable content")
    // Retrieve the available screen content to capture.
    SCShareableContent.getWithCompletionHandler { availableContent, error in
      guard let availableContent = availableContent else {
        self.error("no available content: \(String(describing: error))")
        return
      }
      guard let display = availableContent.displays.first else {  // TODO: multi-display support
        self.error("no displays")
        return
      }
      // print("using display \(display.debugDescription)")
      DispatchQueue.main.async {
        self.startScreenCapture(display)
      }
    }
  }

  func startScreenCapture(_ display: SCDisplay) {
    time("start screen capture")

    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

    let streamConfig = SCStreamConfiguration()
    // TODO: get scaleFactor for selected display, not just main screen
    // TODO: would scaleFactor = 1 provide better a better latency-to-accuracy ratio?
    let scaleFactor = Int(NSScreen.main?.backingScaleFactor ?? 2)
    // print("display:", display.width, "x", display.height, "@", scaleFactor)
    streamConfig.width = display.width * scaleFactor
    streamConfig.height = display.height * scaleFactor
    self.size = CGSize(width: display.width, height: display.height)

    // Set the capture interval and queue depth low (1 fps, 1 buffer).
    // We will be stopping it after the first frame.
    streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    streamConfig.queueDepth = 1

    // Start the stream and await new video frames.
    let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
    self.stream = stream  // keep stream alive!
    try! stream.addStreamOutput(
      self, type: .screen, sampleHandlerQueue: self.videoSampleBufferQueue)
    stream.startCapture()
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    // Return early if the sample buffer is invalid.
    guard sampleBuffer.isValid else {
      self.error("received invalid sample buffer")
      return
    }
    stream.stopCapture { err in
      if err != nil {
        self.error("failed to stop capture \(err.debugDescription)")
      }
      self.stream = nil  // all done with it
      DispatchQueue.main.async {
        self.startOCR(sampleBuffer)
      }
    }
  }

  func startOCR(_ buffer: CMSampleBuffer) {
    time("OCR start")
    let requestHandler = VNImageRequestHandler(cmSampleBuffer: buffer)
    let request: VNRecognizeTextRequest = VNRecognizeTextRequest { request, error in
      self.recognizeTextHandler(request: request, error: error)
    }
    request.recognitionLevel = .fast  // .accurate is too slow
    try! requestHandler.perform([request])
  }

  func recognizeTextHandler(request: VNRequest, error: Error?) {
    time("OCR callback")
    guard let observations = request.results as? [VNRecognizedTextObservation] else {
      self.error("wrong observation type")
      return
    }
    var locs = locationsForString(observations, self.request)
    if let near = self.near {
      let nearby: [XYC] = locationsForString(observations, near)
      if nearby.count > 0 {
        // quadratic! whee!
        locs.indices.forEach({ i in
          var xyc: XYC = locs[i]
          var bestScore: Float = -1
          nearby.forEach({ n in
            let score = hypotf(Float(n.x - xyc.x), Float(n.y - xyc.y))
            if bestScore == -1 || score < bestScore {
              bestScore = score
            }
          })
          xyc.c = bestScore
          locs[i] = xyc
        })
      }
    }
    print("found \(self.request) near \(self.near ?? "-") at \(locs)")
    DispatchQueue.main.async {
      self.chooseDestAndMoveMouse(locs)
    }
  }

  func chooseDestAndMoveMouse(_ locs: [XYC]) {
    time("choose destination")
    if locs.count == 0 {
      self.error("no dests")
      return
    }
    var bestScore: Float = -1
    var best: XYC = locs[0]
    locs.forEach({ xyc in
      if bestScore == -1 || xyc.c < bestScore {
        bestScore = xyc.c
        best = xyc
      }
    })
    CGDisplayMoveCursorToPoint(CGMainDisplayID(), CGPoint(x: best.x, y: best.y))
    exit(0)
  }

  func locationsForString(_ observations: [VNRecognizedTextObservation], _ s: String) -> [XYC] {
    var locs: [CGRect: Float] = [:]
    for observation in observations {
      let cands = observation.topCandidates(1)  // TODO: >1?
      for candidate in cands {
        // This is a silly hack to work around a Serenade quirk:
        // It prints the query onscreen, and then we mouse to it.
        // TODO: Fix on the Serenade side instead by adding an API to hide
        // the choices, and then calling it before calling mouseto.
        if candidate.string.contains("mouse to") {
          continue
        }
        guard let range = candidate.string.range(of: s, options: .caseInsensitive) else {
          // substring not present
          continue
        }
        guard let boundingBox = try? candidate.boundingBox(for: range) else {
          // failed to extract interior bounding box
          continue
        }
        // Convert the rectangle from normalized coordinates to image coordinates.
        let rect = VNImageRectForNormalizedRect(
          boundingBox.boundingBox, Int(self.size.width), Int(self.size.height))
        // If there are multiple matches at the same spot, pick the one with the highest confidence.
        if locs[rect] ?? 0 < candidate.confidence {
          locs[rect] = candidate.confidence
        }
      }
    }

    // Convert map of rect -> confidence to array of screen coordinate + confidences for return.
    var out: [XYC] = []
    locs.forEach { rect, confidence in
      let mid = XYC(
        x: Int(rect.minX + rect.width / 2),
        y: Int(self.size.height - (rect.minY + rect.height / 2)),
        c: confidence  // TODO: this is unused for now; incorporate it?
      )
      out.append(mid)
    }
    return out
  }

}

struct XYC: Codable {
  var x, y: Int
  var c: Float
}

extension CGRect: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(minX)
    hasher.combine(minY)
    hasher.combine(maxX)
    hasher.combine(maxY)
  }
}

extension CGRect {
  var center: CGPoint { .init(x: midX, y: midY) }
}
