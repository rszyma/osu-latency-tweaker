{
  lib,
  writeShellApplication,
  alsa-utils, # aplay
  coreutils, # realpath, mktemp, chmod --reference
  fzf,
  jq,
  pipewire, # pw-dump
  psmisc, # fuser
  wireplumber, # wpctl
  osu-lazer-bin-patched,
}:
writeShellApplication {
  name = "osu-lazer-launcher";
  runtimeInputs = [
    alsa-utils
    coreutils
    fzf
    jq
    pipewire
    psmisc
    wireplumber
  ];
  text = ''
    OSU_GAME=${lib.getExe osu-lazer-bin-patched}
  ''
  + builtins.readFile ./osu-lazer-launcher.sh;
}
