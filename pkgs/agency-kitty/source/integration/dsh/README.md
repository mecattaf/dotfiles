# Native Kitty sessions in DSH

This optional plugin exposes the canonical NAS Kitty session catalogue to an
existing DSH Host. It does not mount a terminal renderer, create a second DSH
Host, start provider sessions, or insert a proxy into terminal input.

`kitty_native_sessions` returns durable terminal IDs, linked DSH chat IDs,
canonical NAS directories, optional Imagine workspace references, and the
native Kitty application class. One terminal may be linked to several chats;
no fixed workspace count is imposed. Imagine remains responsible for actual
window membership and layout. A saved workspace reference is a relationship,
not proof that a window is currently there.

Install `agency-kitty` on NAS and set `config.command` to its immutable absolute
path. The Nix package renders its immutable helper path into the bundle patch;
the source token must never be mounted without that substitution. Add the
package through the existing Cordis profile/bundle mechanism. The package
declares `dsh.bundle.patch`, so ordinary profile discovery registers it.
It never self-installs or restarts
the production Host. All tool operations are read-only metadata operations.
Use the explicit terminal UUID in the human launcher to reconnect.

This adapter intentionally does not relabel these sessions as DSH-owned PTYs.
The existing DSH `server/epoch/session/terminal` route protocol and this
`agency-kitty` terminal identity are separate providers. Existing web chat
viewers continue to use the DSH chat ID; Kitty continues to render the TUI.
