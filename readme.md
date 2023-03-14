mouseto is a little macOS script I hacked together for use with voice control systems like serenade.ai.

Run it like this:

```sh
$ mouseto edit
```

and it will OCR the screen and move the cursor to an instance of the word "edit" on screen.
See the Grammar section below if you find it is guessing the wrong word instance.

I have it integrated with Serenade as a custom command:

```javascript
serenade.global().command("mouse to <%text%>", async (api, matches) => {
  await api.runShell("/YOUR_FAVORITE_PATH/mouseto/", [
    matches.text,
  ]);
});
```

(Note that you can use `api.click` to cause mouse clicks.)

Integration instructions for Talon and keyboard control systems welcome.


### Installation

You're pretty much on your own, sorry.
I don't really know how to hold swift dev tools.
Here's what I do:

```sh
$ xcodebuild && mv build/Release/mouseto /YOUR_FAVORITE_PATH/mouseto
```

You will probably need to do something with codesigning or something.
README improvements welcomed here. :)

You will also need to give any app running mouseto (Terminal, Serenade, etc.) screen recording and control permissions in System Preferences.


### Grammar

Because the same word often occurs in multiple places you can use "near" to disambiguate.
If you run `mouseto edit near file`, it'll mouse to the word edit that is nearest to a word file on screen.

I expect the grammar may grow more complicated over time.


### TODOs

This is a list of things I want to improve/do.

* On start-up, jiggle or animate the cursor so the user knows the process has started.
  If nothing ends up happening (e.g. the desired word is not found), this will make it clearer whether `mouseto` got invoked at all. It'll also make it feel more responsive.
* Animate cursor movement, so instead of leaping to the destination, the cursor glides there. Probably. This might be a bad idea. If it is, consider jiggling or animating the cursor in its destination after movement.
* Support multiple "near" terms combined with "and", such as `mouseto edit near file and view`.
* Consider adding click support and moving more of the grammar to the app. So `mouse <%text%>` would become the Serenade command, and it would execute things like `mouseto to edit` to move and `mouseto click on edit` to move and click. And `mouseto double click`, `mouseto right click`, and so so.
* Think about disambiguation. I'd like to allow the grammar to be ambiguous and use the screen contents and some heuristics to do the disambiguation. It might be nice to highlight all of the found instances and let the user select from them, but I really enjoy the statelessness of the current design, and I have found that "near" suffices to disambiguate almost always.
* Incorporate homophones ("1"/"one"), ("dear"/"deer").
* Incorporate Levenstein distance or some other fuzzy matcher.
* Add unit tests.
* Allow people to have a folder of named icons. Then `mouseto next` would potentially match the word "next" and any icons with filename "next_NN".
* Add other ways to specify mouse movement. Like `mouseto up`, `mouseto menu bar`, `mouseto tabs`, `mouseto bottom of window`, `mouseto top of screen`, and so many more. There are a lot of possibilities here; it'll take some thinking and experimenting to figure out the right set.
* Reduce latency. The two slow things are getting the screen grab and doing the OCR.
  Speeding up the screen grab would probably require staying resident, which I would rather avoid.
  We could probably speed up the OCR by down sampling, but that would also likely affect accuracy.
  Experimentation is required.


### Contributing

PRs are welcome.
However, please anticipate slow review times.
I'm not proud of that, it's just a fact.

I will be most excited about bug fixes and implementation of todos in the list above.
Please keep any code as simple as possible and avoid introducing new dependencies if at all possible.
I would like people to be able to rapidly scan the code and convince themselves that it is something that they are comfortable running on their machines.

This is the first Swift that I have ever written, so it probably is not idiomatic at all.
I am open to pull requests improving the code style, but please do not rewrite the entire thing.
Sending several pull requests, each improving one isolated aspect, is much more likely to yield a mutually satisfactory result.
And please explain why the change is good, so that I may learn.

The code is formatted using swift-format.


### License

MIT License
