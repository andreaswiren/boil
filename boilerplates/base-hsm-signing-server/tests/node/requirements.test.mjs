import test from "node:test"; import assert from "node:assert/strict"; import fs from "node:fs";
test("security boilerplate contains forbidden-interface invariant",()=>{const s=fs.readFileSync("AGENTS.md","utf8");assert.match(s,/generic remote shell/i);assert.match(s,/PKCS#11/i)});
test("installer never uses chmod 777",()=>{assert.doesNotMatch(fs.readFileSync("install.sh","utf8"),/chmod\s+777/)});
