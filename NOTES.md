`pomodori setup`:

 * The server is the primary source of truth, not the local manifest. Prefer autodetecting state from the server instead of reading state from the manifest.
 * Try not to completely alter the status quo of the server, but to use it.

`pomodori deploy`:

 * `pomodori deploy` can consider `pomodori-setup.json` on the server as the primary source of truth. It should check whether the local manifest is in sync with the remote manifest.
