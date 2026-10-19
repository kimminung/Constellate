"""Korean pronunciation check with SenseVoice (sherpa-onnx): transcribe a wav and score CER against the TTS text."""
import os
import re
import unicodedata

import numpy as np
import sherpa_onnx
import soundfile as sf

SV_DIR = os.environ.get(
    "SV_DIR",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "models", "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"),
)
_rec = None

# ASR sometimes writes loanwords in Latin script or digits; map them to the Hangul used in the script.
LATIN = {
    "ai": "에이아이", "ui": "유아이", "sharepay": "셰어플레이", "shareplay": "셰어플레이", "facetime": "페이스타임",
    "constellate": "컨스텔레이트", "ipad": "아이패드", "mac": "맥", "visionpro": "비전프로", "vision": "비전", "pro": "프로",
    "siri": "시리", "orbit": "오빗", "notes": "노트", "state": "스테이트", "markdown": "마크다운", "newer": "뉴어", "older": "올더",
    "o": "오", "l": "엘", "v": "브이",
}
DIGITS = {"0": "영", "1": "일", "2": "이", "3": "삼", "4": "사", "5": "오", "6": "육", "7": "칠", "8": "팔", "9": "구"}


def get_rec():
    global _rec
    if _rec is None:
        _rec = sherpa_onnx.OfflineRecognizer.from_sense_voice(
            model=f"{SV_DIR}/model.int8.onnx", tokens=f"{SV_DIR}/tokens.txt", language="ko", use_itn=False, num_threads=2,
        )
    return _rec


def transcribe(path):
    audio, sr = sf.read(path, dtype="float32", always_2d=True)
    audio = audio.mean(axis=1)
    if sr != 16000:
        n = int(len(audio) * 16000 / sr)
        audio = np.interp(np.linspace(0, len(audio) - 1, n), np.arange(len(audio)), audio).astype(np.float32)
        sr = 16000
    rec = get_rec()
    s = rec.create_stream()
    s.accept_waveform(sr, audio)
    rec.decode_stream(s)
    return s.result.text


def normalize(text):
    text = unicodedata.normalize("NFC", text.lower())
    text = re.sub(r"<\|[^|]*\|>", "", text)  # SenseVoice tags
    for k in sorted(LATIN, key=len, reverse=True):
        text = re.sub(rf"(?<![a-z]){re.escape(k)}(?![a-z])", LATIN[k], text)
    text = "".join(DIGITS.get(c, c) for c in text)
    return "".join(c for c in text if "가" <= c <= "힣")


def cer(ref, hyp):
    r, h = normalize(ref), normalize(hyp)
    if not r:
        return 0.0
    prev = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        cur = [i] + [0] * len(h)
        for j in range(1, len(h) + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r[i - 1] != h[j - 1]))
        prev = cur
    return prev[-1] / len(r)


if __name__ == "__main__":
    import sys
    hyp = transcribe(sys.argv[1])
    print(hyp)
    if len(sys.argv) > 2:
        print("CER", round(cer(sys.argv[2], hyp), 3))
