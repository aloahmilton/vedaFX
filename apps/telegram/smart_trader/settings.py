import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
ALLOWED_CHAT_ID = os.getenv("TELEGRAM_ALLOWED_CHAT_ID", "").strip()
MT5_TERMINAL_PATH = os.getenv("MT5_TERMINAL_PATH", "").strip()
MT5_SYMBOL = os.getenv("MT5_SYMBOL", "EURUSD").strip()
MT5_MAGIC = int(os.getenv("MT5_MAGIC", "26112201"))
POLL_SECONDS = int(os.getenv("POLL_SECONDS", "15"))

def common_files_dir() -> Path:
    # Standard MetaQuotes common files path on Windows.
    appdata = os.getenv("APPDATA")
    if not appdata:
        raise RuntimeError("APPDATA is not set. Run this monitor on Windows.")
    return Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"

def validate_settings():
    if not BOT_TOKEN:
        raise RuntimeError("Set TELEGRAM_BOT_TOKEN in your .env file.")
    if not ALLOWED_CHAT_ID:
        raise RuntimeError("Set TELEGRAM_ALLOWED_CHAT_ID in your .env file.")
