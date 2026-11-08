# Existing chat catalogue bridge

`native_catalogue.py` is a companion to the existing NAS `catalogue_nas.py`.
The package renders its fixed helper path. It reads native terminal metadata
inside the existing ten-second inventory worker; it adds no daemon, PTY owner,
client DSH Host, input relay or polling clock. The client relay already forwards
unknown NDJSON frames unchanged.

`catalogue-nas.patch` targets the deployed source whose SHA256 is
`dc2e866152e0a1b1b3165cfeeb2a06525babbabbafb01a10a38be5807e08c60e`.
Apply only to a new owned release with that exact source, install the rendered
companion beside it, and preserve the existing attention-reader/client release
contents. The worker is joined during shutdown and the metadata child has a
five-second deadline and four-MiB output bound. This patch has not modified the
live release.

The corresponding Imagine patch is `../imagine/native-catalogue.patch`, after
the separately qualified native drag fix. Set its existing `sessionCatalogue`
configuration's `nativeTerminalLauncher` to the installed **absolute**
`agency-kitty` path. Its human resume action sends a bounded typed stdin request
using the fixed `desktop-resume-request` subcommand. NAS must confirm that exact
terminal UUID is live, persistent and still linked to the selected chat.
Unknown, dead, direct, unlinked and ambiguous routes never create a substitute.

DSH-owned PTYs keep their existing route and launcher. Native Kitty terminals
have a separate provider and UUID. Chat IDs, terminal IDs and desktop classes
remain distinct. Native tabs can share an OS-window class: the catalogue can
focus that OS window, but does not claim to focus a specific Kitty tab.
No live desktop or catalogue release is changed by installing this package.
