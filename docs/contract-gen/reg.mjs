// --import hook: tepira's own handler-test resolve hooks (@/ alias, stubs).
import { register } from "node:module";
import { pathToFileURL } from "node:url";
if (!process.env.TEPIRA_REPO) throw new Error("set TEPIRA_REPO");
register(pathToFileURL(process.env.TEPIRA_REPO + "/test/harness/hooks.mjs").href, import.meta.url);
