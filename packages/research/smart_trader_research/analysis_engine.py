"""Offline/research signal analysis. This module does not place orders."""
from __future__ import annotations
import pandas as pd

def ema(series: pd.Series, period: int) -> pd.Series:
    return series.ewm(span=period, adjust=False).mean()

def rsi(series: pd.Series, period: int = 14) -> pd.Series:
    delta = series.diff()
    gain = delta.clip(lower=0).ewm(alpha=1/period, adjust=False).mean()
    loss = (-delta.clip(upper=0)).ewm(alpha=1/period, adjust=False).mean()
    rs = gain / loss.replace(0, float("nan"))
    return 100 - (100 / (1 + rs))

def atr(frame: pd.DataFrame, period: int = 14) -> pd.Series:
    prev_close = frame["close"].shift(1)
    tr = pd.concat([
        frame["high"] - frame["low"],
        (frame["high"] - prev_close).abs(),
        (frame["low"] - prev_close).abs()
    ], axis=1).max(axis=1)
    return tr.ewm(alpha=1/period, adjust=False).mean()

def analyze_signal(h4: pd.DataFrame, h1: pd.DataFrame, m15: pd.DataFrame,
                   structure_lookback: int = 12,
                   liquidity_lookback: int = 10) -> dict:
    """Return BUY/SELL/WAIT using closed candles only.

    Frames must be chronological and contain open/high/low/close columns.
    This is a research mirror of the EA rules, not an execution interface.
    """
    required = {"open", "high", "low", "close"}
    for name, frame in (("h4", h4), ("h1", h1), ("m15", m15)):
        if not required.issubset(frame.columns):
            raise ValueError(f"{name} must contain {sorted(required)}")
    if len(h4) < 205 or len(h1) < structure_lookback + 2 or len(m15) < liquidity_lookback + 2:
        return {"signal": "WAIT", "reason": "Insufficient history"}

    h4c = h4["close"]
    fast, slow = ema(h4c, 50).iloc[-2], ema(h4c, 200).iloc[-2]
    last_h4 = h4.iloc[-2]["close"]
    trend = "BULL" if last_h4 > fast > slow else (
        "BEAR" if last_h4 < fast < slow else "NONE"
    )

    h1_signal = h1.iloc[-2]
    h1_prior = h1.iloc[-(structure_lookback+2):-2]
    struct_bull = h1_signal["close"] > h1_prior["high"].max()
    struct_bear = h1_signal["close"] < h1_prior["low"].min()

    signal_candle = m15.iloc[-2]
    prior = m15.iloc[-(liquidity_lookback+2):-2]
    swept_low = signal_candle["low"] < prior["low"].min() and signal_candle["close"] > prior["low"].min()
    swept_high = signal_candle["high"] > prior["high"].max() and signal_candle["close"] < prior["high"].max()
    rsi_value = rsi(m15["close"]).iloc[-2]
    atr_value = atr(m15).iloc[-2]

    if trend == "BULL" and struct_bull and swept_low and signal_candle["close"] > signal_candle["open"] and rsi_value >= 52:
        return {"signal": "BUY", "reason": "H4 bullish + H1 break + M15 sell-side sweep/reclaim + bullish candle + RSI", "rsi": float(rsi_value), "atr": float(atr_value)}
    if trend == "BEAR" and struct_bear and swept_high and signal_candle["close"] < signal_candle["open"] and rsi_value <= 48:
        return {"signal": "SELL", "reason": "H4 bearish + H1 break + M15 buy-side sweep/rejection + bearish candle + RSI", "rsi": float(rsi_value), "atr": float(atr_value)}
    return {"signal": "WAIT", "reason": f"No complete setup (trend={trend}, RSI={float(rsi_value):.1f})"}
