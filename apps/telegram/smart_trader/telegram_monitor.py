from __future__ import annotations
import asyncio
import logging
from pathlib import Path

import MetaTrader5 as mt5
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

from . import settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("smart_trader")

def authorized(update: Update) -> bool:
    return bool(update.effective_chat and str(update.effective_chat.id) == settings.ALLOWED_CHAT_ID)

def mt5_connect() -> bool:
    kwargs = {}
    if settings.MT5_TERMINAL_PATH:
        kwargs["path"] = settings.MT5_TERMINAL_PATH
    return bool(mt5.initialize(**kwargs))

def pause_path() -> Path:
    folder = settings.common_files_dir()
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "AI_SMART_TRADER_PAUSE.txt"

def set_pause(value: str):
    # The EA treats an unreadable existing pause file as paused (fail closed).
    pause_path().write_text(value, encoding="ascii")

async def deny(update: Update):
    if update.message:
        await update.message.reply_text("Not authorized.")

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not authorized(update): return await deny(update)
    await update.message.reply_text(
        "AI SMART TRADER FX v1.0\n"
        "Mode: DEMO ONLY\n"
        "Commands: /status /positions /pause /resume /help"
    )

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not authorized(update): return await deny(update)
    await update.message.reply_text(
        "/status - MT5 account and terminal status\n"
        "/positions - current open positions\n"
        "/pause - block new EA entries\n"
        "/resume - allow new entries (demo lock remains active)"
    )

async def status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not authorized(update): return await deny(update)
    if not mt5_connect():
        await update.message.reply_text(f"MT5 unavailable: {mt5.last_error()}")
        return
    try:
        account = mt5.account_info()
        terminal = mt5.terminal_info()
        if account is None:
            await update.message.reply_text("MT5 connected, but account information is unavailable.")
            return
        mode = "DEMO" if account.trade_mode == mt5.ACCOUNT_TRADE_MODE_DEMO else "NON-DEMO"
        await update.message.reply_text(
            f"AI SMART TRADER FX\n"
            f"Connection: {'connected' if terminal and terminal.connected else 'not connected'}\n"
            f"Account mode: {mode}\n"
            f"Balance: {account.balance:.2f} {account.currency}\n"
            f"Equity: {account.equity:.2f} {account.currency}\n"
            f"Symbol: {settings.MT5_SYMBOL}"
        )
    finally:
        mt5.shutdown()

async def positions(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not authorized(update): return await deny(update)
    if not mt5_connect():
        await update.message.reply_text(f"MT5 unavailable: {mt5.last_error()}")
        return
    try:
        items = mt5.positions_get(symbol=settings.MT5_SYMBOL) or []
        items = [p for p in items if p.magic == settings.MT5_MAGIC]
        if not items:
            await update.message.reply_text("No AI Smart Trader positions are open.")
            return
        lines = ["AI SMART TRADER OPEN POSITIONS"]
        for p in items:
            side = "BUY" if p.type == mt5.POSITION_TYPE_BUY else "SELL"
            lines.append(f"{side} {p.symbol} vol={p.volume} entry={p.price_open} P/L={p.profit:.2f}")
        await update.message.reply_text("\n".join(lines))
    finally:
        mt5.shutdown()

async def pause(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not authorized(update): return await deny(update)
    try:
        set_pause("PAUSE")
        await update.message.reply_text("Paused: EA will not open new trades. Existing broker-side SL/TP remain active.")
    except Exception as exc:
        await update.message.reply_text(f"Could not write pause control file: {exc}")

async def resume(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not authorized(update): return await deny(update)
    try:
        set_pause("RUN")
        await update.message.reply_text("New entries enabled. The EA's demo-only and risk protections remain active.")
    except Exception as exc:
        await update.message.reply_text(f"Could not write resume control file: {exc}")

async def main():
    settings.validate_settings()
    app = Application.builder().token(settings.BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("status", status))
    app.add_handler(CommandHandler("positions", positions))
    app.add_handler(CommandHandler("pause", pause))
    app.add_handler(CommandHandler("resume", resume))
    log.info("Telegram monitor starting. Authorized chat ID is configured.")
    await app.initialize()
    await app.start()
    await app.updater.start_polling()
    try:
        await asyncio.Event().wait()
    finally:
        await app.updater.stop()
        await app.stop()
        await app.shutdown()

if __name__ == "__main__":
    asyncio.run(main())
