class CameraSettingsMsg {
  static const cameraSettingsMsgType = 0x0d;

  static List<int> pack(int qualityIndex, int autoExpGainTimes, int meteringModeIndex, double exposure, double shutterKp, int shutterLimit, double gainKp, int gainLimit) {
    // exposure is a double in the range -2.0 to 2.0, so map that to an unsigned byte 0..255
    // by multiplying by 64, adding 128 and truncating
    int intExp;
    if (exposure >= 2.0) {
      intExp = 255;
    }
    else if (exposure <= -2.0) {
      intExp = 0;
    }
    else {
      intExp = ((exposure * 64) + 128).floor();
    }

    int intShutKp = (shutterKp * 10).toInt() & 0xFF;
    int intShutLimMsb = (shutterLimit >> 8) & 0xFF;
    int intShutLimLsb = shutterLimit & 0xFF;
    int intGainKp = (gainKp * 10).toInt() & 0xFF;

    // data byte 0x01, MSG_TYPE 0x0d, msg_length(Uint16), then 9 bytes of camera settings
    return [0x01, cameraSettingsMsgType, 0, 9, qualityIndex & 0xFF, autoExpGainTimes & 0xFF, meteringModeIndex & 0xFF,
            intExp, intShutKp, intShutLimMsb, intShutLimLsb, intGainKp, gainLimit & 0xFF];
  }
}
