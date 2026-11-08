This independent extraction proof ran on strix-coordinator through runtime-test.

- Upstream preservation and own-entry boundary: passed.
- Pure tests: 46 passed, 0 failed, 178 assertions across three files.
- Standard Vite build: passed; shell.js and options.json emitted.
- Source map: ImagineShell and own Desktop present; reference shell absent.
- No compositor, config builder, registry install, Nix build or client changes.

The source snapshot is the initial extraction before ChromeVisibility feature
files were added. Its complete private fixture and original logs remain at:

`/home/tom/compute/imagine-extraction-20261105/.proof/pinned-20261105T203726.815945Z`

Copied logs preserve their messages; trailing spaces in build.log were removed.
After this proof, the Vite config's local options import gained its explicit
`.ts` extension to address Vite's future-loader warning. No production logic
changed. Vite also reported the existing large single shell chunk.
