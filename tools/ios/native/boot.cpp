// ECHOES: start the iOS share sheet helper (EchoesShare.swift) when the app loads.
extern "C" void echoes_share_boot(void);
__attribute__((constructor)) static void echoes_share_ctor(void) { echoes_share_boot(); }
