import pandas as pd
from smart_trader_research.analysis_engine import analyze_signal, ema, rsi

def frame(n=250, start=1.0, step=0.0001):
    close = [start + i * step for i in range(n)]
    return pd.DataFrame({
        "open": [x-step/3 for x in close],
        "high": [x+step for x in close],
        "low": [x-step for x in close],
        "close": close,
    })

def test_ema_returns_series():
    s = pd.Series([1, 2, 3, 4, 5], dtype=float)
    assert len(ema(s, 3)) == 5

def test_rsi_returns_series():
    s = pd.Series([1, 2, 1.5, 2.5, 3, 2.8, 3.5] * 5, dtype=float)
    assert len(rsi(s)) == len(s)

def test_insufficient_history_waits():
    short = frame(20)
    result = analyze_signal(short, short, short)
    assert result["signal"] == "WAIT"
    assert "Insufficient" in result["reason"]
