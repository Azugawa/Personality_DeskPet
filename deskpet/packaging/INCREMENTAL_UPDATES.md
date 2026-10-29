# Incremental resource updates

First installation still uses Inno Setup. Version 0.2.5 installs DeskPetUpdater.exe once.
Subsequent compatible releases download only missing 1 MiB SHA-256 resource chunks,
reconstruct and verify DeskPet.pck, then exit, atomically replace the resource pack,
and restart without an installer wizard. The previous resource pack is retained as
DeskPet.pck.backup. Engine changes still require an installer.

Release assets must include:
- DeskPet-Setup-VERSION.exe (initial installation and legacy clients)
- update.json
- Every chunk file referenced by update.json.resource_update.chunks

Publish as a draft first; verify every referenced chunk exists before marking latest.
Do not publish only the installer and update.json as with older releases.
The manifest retains the installer URL/hash so old clients remain compatible.
Fixed-size chunk reuse is content-hash based. Resource-pack layout changes may shift
many blocks, so some releases can still download most of the resource pack. This is
not a guarantee that every update is small, but the Godot executable is not normally
redownloaded and no installation wizard is launched.

Validation performed: complete chunk reconstruction and SHA-256 equality; isolated
helper test verified pack replacement, old-file backup and application restart.
End-to-end online upgrade requires publishing a later compatible release.
