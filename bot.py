#!/usr/bin/env python3
"""
Advanced Telegram Bot (full features requested)
- Menus: DTAC / TRUE / AIS
- Contact Admin, Donate (TrueMoney QR)
- Admin panel with PIN login
- Admin upload files per-category, with optional expiry
- Multi-file listing & choose which file to download
- Auto-delete expired files (background)
- Broadcast text / photo / document (admin)
- Users auto-register with timestamp, /me shows profile
"""

import os
import json
import time
import asyncio
import logging
import base64
from pathlib import Path
from typing import Dict, Optional
from datetime import datetime, timedelta

from telegram import (
    Update,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    InputFile,
)
from telegram.ext import (
    ApplicationBuilder,
    CommandHandler,
    ContextTypes,
    CallbackQueryHandler,
    MessageHandler,
    filters,
)

# ---------------------------
# CONFIG / ENV
# ---------------------------
BOT_TOKEN = os.environ.get("BOT_TOKEN", "")
ADMIN_ID_ENV = os.environ.get("ADMIN_ID")  # optional
ADMIN_PIN = os.environ.get("ADMIN_PIN", "1234")  # default PIN
if ADMIN_ID_ENV:
    try:
        ADMIN_ID = int(ADMIN_ID_ENV)
    except:
        ADMIN_ID = 0
else:
    ADMIN_ID = 0

ADMIN_USERNAME = "@Juevpn"

TRUEMONEY_NUMBER = "0953244179"
TRUEMONEY_QR_PATH = Path("assets/true_qr.png")

BASE_DIR = Path("files")
BASE_DIR.mkdir(exist_ok=True)

USERS_JSON = Path("users.json")
if not USERS_JSON.exists():
    USERS_JSON.write_text(json.dumps({}))

# Rate limit safety
DELAY_BETWEEN = float(os.environ.get("DELAY_BETWEEN", "0.05"))

# Broadcast & upload states
broadcast_state: Dict[int, dict] = {}  # admin_id -> state
upload_state: Dict[int, str] = {}  # admin_id -> category key

# Admin sessions (after PIN login)
admin_sessions: Dict[int, float] = {}  # user_id -> expiry_timestamp

# Categories
CATEGORIES = {
    "dtac_game_plan": "DTAC GAME PLAN",
    "dtac_zivpn": "DTAC ZIVPN",
    "dtac_nopro": "DTAC NOPRO",
    "true_twitter": "TRUE TWITTER PLAN",
    "true_viber": "TRUE VIBER PLAN",
    "ais_v2ray_64": "V2RAY 64KBPS",
}

# Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


# ---------------------------
# Helper utilities
# ---------------------------
def safe_encode_filename(name: str) -> str:
    b = name.encode("utf-8")
    return base64.urlsafe_b64encode(b).decode("ascii")


def safe_decode_filename(token: str) -> str:
    try:
        b = base64.urlsafe_b64decode(token.encode("ascii"))
        return b.decode("utf-8")
    except Exception:
        return token


def category_folder(cat_key: str) -> Path:
    p = BASE_DIR / cat_key
    p.mkdir(parents=True, exist_ok=True)
    # ensure metadata exists
    meta = p / "metadata.json"
    if not meta.exists():
        meta.write_text(json.dumps({}))
    return p


def load_metadata(cat_key: str) -> dict:
    p = category_folder(cat_key) / "metadata.json"
    try:
        return json.loads(p.read_text())
    except:
        return {}


def save_metadata(cat_key: str, data: dict):
    p = category_folder(cat_key) / "metadata.json"
    p.write_text(json.dumps(data))


def list_category_files(cat_key: str):
    folder = category_folder(cat_key)
    files = [f for f in folder.iterdir() if f.is_file() and f.name != "metadata.json"]
    files_sorted = sorted(files, key=lambda x: x.stat().st_mtime, reverse=True)
    return files_sorted


def register_user(user_id: int, username: Optional[str]):
    data = json.loads(USERS_JSON.read_text())
    sid = str(user_id)
    if sid not in data:
        data[sid] = {"username": username or "", "first_seen": int(time.time())}
        USERS_JSON.write_text(json.dumps(data))


def get_all_users():
    data = json.loads(USERS_JSON.read_text())
    return list(data.keys())


def is_admin_session(uid: int) -> bool:
    # admin is valid if in admin_sessions and not expired, or matches ADMIN_ID env if set
    if ADMIN_ID and uid == ADMIN_ID:
        return True
    exp = admin_sessions.get(uid)
    if exp and time.time() < exp:
        return True
    return False


def start_admin_session(uid: int, minutes: int = 60):
    admin_sessions[uid] = time.time() + minutes * 60


# ---------------------------
# UI builders
# ---------------------------
def build_main_menu():
    keyboard = [
        [InlineKeyboardButton("DTAC", callback_data="menu_dtac")],
        [InlineKeyboardButton("TRUE", callback_data="menu_true")],
        [InlineKeyboardButton("AIS", callback_data="menu_ais")],
        [InlineKeyboardButton("📞 Contact Admin", callback_data="contact_admin"),
         InlineKeyboardButton("💳 Donate", callback_data="donate_menu")],
        [InlineKeyboardButton("👤 My Profile", callback_data="my_profile"),
         InlineKeyboardButton("⚙️ Admin Panel", callback_data="admin_panel")],
    ]
    return InlineKeyboardMarkup(keyboard)


def build_dtac_menu():
    keyboard = [
        [InlineKeyboardButton("DTAC GAME PLAN", callback_data="cat:dtac_game_plan")],
        [InlineKeyboardButton("DTAC ZIVPN", callback_data="cat:dtac_zivpn")],
        [InlineKeyboardButton("DTAC NOPRO", callback_data="cat:dtac_nopro")],
        [InlineKeyboardButton("🔙 Back", callback_data="back_main")],
    ]
    return InlineKeyboardMarkup(keyboard)


def build_true_menu():
    keyboard = [
        [InlineKeyboardButton("TRUE TWITTER PLAN", callback_data="cat:true_twitter")],
        [InlineKeyboardButton("TRUE VIBER PLAN", callback_data="cat:true_viber")],
        [InlineKeyboardButton("🔙 Back", callback_data="back_main")],
    ]
    return InlineKeyboardMarkup(keyboard)


def build_ais_menu():
    keyboard = [
        [InlineKeyboardButton("V2RAY 64KBPS", callback_data="cat:ais_v2ray_64")],
        [InlineKeyboardButton("🔙 Back", callback_data="back_main")],
    ]
    return InlineKeyboardMarkup(keyboard)


# ---------------------------
# Background cleanup task
# ---------------------------
async def cleanup_expired_loop(app):
    """Runs in background, deletes expired files every hour."""
    while True:
        try:
            for cat in list(CATEGORIES.keys()):
                meta = load_metadata(cat)
                changed = False
                for fname, info in list(meta.items()):
                    exp_ts = info.get("expiry_ts", 0)
                    if exp_ts and time.time() >= exp_ts:
                        # delete file if exists
                        fpath = category_folder(cat) / fname
                        if fpath.exists():
                            try:
                                fpath.unlink()
                                logger.info("Deleted expired file %s", fpath)
                            except Exception:
                                logger.exception("Failed to delete %s", fpath)
                        meta.pop(fname, None)
                        changed = True
                if changed:
                    save_metadata(cat, meta)
        except Exception:
            logger.exception("cleanup loop error")
        # sleep one hour
        await asyncio.sleep(3600)


# ---------------------------
# Handlers
# ---------------------------
async def start_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    register_user(user.id, user.username)
    # greet
    await update.message.reply_text("မင်္ဂလာပါ! လိုချင်တဲ့ service ကို ရွေးပါ။", reply_markup=build_main_menu())


async def callback_query_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    data = query.data or ""

    # Navigation
    if data == "menu_dtac":
        await query.edit_message_text("DTAC အပိုင်း — ရွေးချယ်ပါ:", reply_markup=build_dtac_menu())
        return
    if data == "menu_true":
        await query.edit_message_text("TRUE အပိုင်း — ရွေးချယ်ပါ:", reply_markup=build_true_menu())
        return
    if data == "menu_ais":
        await query.edit_message_text("AIS အပိုင်း — ရွေးချယ်ပါ:", reply_markup=build_ais_menu())
        return
    if data == "back_main":
        await query.edit_message_text("Main menu:", reply_markup=build_main_menu())
        return

    # Contact Admin
    if data == "contact_admin":
        await query.edit_message_text(f"📞 Contact Admin\n\n{ADMIN_USERNAME}", reply_markup=build_main_menu())
        return

    # Donate
    if data == "donate_menu":
        if TRUEMONEY_QR_PATH.exists():
            # send photo then return to menu
            await context.bot.send_photo(chat_id=query.message.chat_id, photo=InputFile(str(TRUEMONEY_QR_PATH)),
                                         caption=f"TrueMoney: `{TRUEMONEY_NUMBER}`", parse_mode="Markdown")
            await query.edit_message_text("Main menu:", reply_markup=build_main_menu())
            return
        else:
            await query.edit_message_text(f"TrueMoney: `{TRUEMONEY_NUMBER}`", parse_mode="Markdown", reply_markup=build_main_menu())
            return

    # My profile
    if data == "my_profile":
        uid = str(query.from_user.id)
        users = json.loads(USERS_JSON.read_text())
        info = users.get(uid, {})
        uname = info.get("username", "")
        first = info.get("first_seen")
        first_str = datetime.utcfromtimestamp(first).strftime("%Y-%m-%d %H:%M UTC") if first else "n/a"
        text = f"👤 User Profile\n\nID: `{uid}`\nUsername: @{uname}\nFirst seen: {first_str}"
        await query.edit_message_text(text, parse_mode="Markdown", reply_markup=build_main_menu())
        return

    # Admin panel
    if data == "admin_panel":
        uid = query.from_user.id
        if not is_admin_session(uid):
            # ask to login with /adminlogin
            await query.edit_message_text("Admin access required. Use /adminlogin <PIN> to start admin session.", reply_markup=build_main_menu())
            return
        # show admin panel buttons
        keyboard = [
            [InlineKeyboardButton("Upload File", callback_data="admin_upload")],
            [InlineKeyboardButton("List Files", callback_data="admin_listfiles"),
             InlineKeyboardButton("Stats", callback_data="admin_stats")],
            [InlineKeyboardButton("Broadcast Text", callback_data="admin_broadcast_text"),
             InlineKeyboardButton("Broadcast Media", callback_data="admin_broadcast_media")],
            [InlineKeyboardButton("Logout", callback_data="admin_logout")],
            [InlineKeyboardButton("🔙 Back", callback_data="back_main")],
        ]
        await query.edit_message_text("Admin Panel", reply_markup=InlineKeyboardMarkup(keyboard))
        return

    # Admin actions
    if data == "admin_logout":
        uid = query.from_user.id
        admin_sessions.pop(uid, None)
        await query.edit_message_text("Admin session ended.", reply_markup=build_main_menu())
        return

    if data == "admin_upload":
        uid = query.from_user.id
        if not is_admin_session(uid):
            await query.edit_message_text("Admin session required. /adminlogin <PIN>", reply_markup=build_main_menu())
            return
        # ask category
        keyboard = [[InlineKeyboardButton(label, callback_data=f"upload:{key}")] for key, label in CATEGORIES.items()]
        keyboard.append([InlineKeyboardButton("Cancel", callback_data="back_main")])
        await query.edit_message_text("Select category to upload to:", reply_markup=InlineKeyboardMarkup(keyboard))
        return

    if data.startswith("upload:"):
        uid = query.from_user.id
        if not is_admin_session(uid):
            await query.edit_message_text("Admin session required. /adminlogin <PIN>", reply_markup=build_main_menu())
            return
        cat = data.split(":", 1)[1]
        upload_state[uid] = cat
        # instructions: admin can attach an optional caption like "expiry:7" to set expiry in days
        await query.edit_message_text(f"Send the file (document) to upload to *{CATEGORIES.get(cat,cat)}*.\n\nOptional: set caption `expiry:7` to expire in 7 days.", parse_mode="Markdown")
        return

    if data == "admin_listfiles":
        uid = query.from_user.id
        if not is_admin_session(uid):
            await query.edit_message_text("Admin session required. /adminlogin <PIN>", reply_markup=build_main_menu())
            return
        # show per-category counts
        lines = []
        for k, label in CATEGORIES.items():
            files = list_category_files(k)
            lines.append(f"{label}: {len(files)} file(s)")
        text = "Files summary:\n\n" + "\n".join(lines)
        await query.edit_message_text(text, reply_markup=build_main_menu())
        return

    if data == "admin_stats":
        uid = query.from_user.id
        if not is_admin_session(uid):
            await query.edit_message_text("Admin session required. /adminlogin <PIN>", reply_markup=build_main_menu())
            return
        users = json.loads(USERS_JSON.read_text())
        text = f"Admin Stats\n\nRegistered users: {len(users)}\nCategories: {len(CATEGORIES)}"
        await query.edit_message_text(text, reply_markup=build_main_menu())
        return

    if data == "admin_broadcast_text":
        uid = query.from_user.id
        if not is_admin_session(uid):
            await query.edit_message_text("Admin session required. /adminlogin <PIN>", reply_markup=build_main_menu())
            return
        # set broadcast_state expecting text (we will use command /broadcast too)
        broadcast_state[uid] = {"mode": "await_text"}
        await query.edit_message_text("Send the text message you want to broadcast to all users (or use /broadcast <text>).")
        return

    if data == "admin_broadcast_media":
        uid = query.from_user.id
        if not is_admin_session(uid):
            await query.edit_message_text("Admin session required. /adminlogin <PIN>", reply_markup=build_main_menu())
            return
        broadcast_state[uid] = {"mode": "await_media"}
        await query.edit_message_text("Send the photo or document to broadcast to all users (you can add caption).")
        return

    # Category selection by user -> list files (if many)
    if data.startswith("cat:"):
        cat = data.split(":", 1)[1]
        files = list_category_files(cat)
        if not files:
            await query.edit_message_text(f"No files for {CATEGORIES.get(cat,cat)} yet.\nContact admin to upload.", reply_markup=build_main_menu())
            return
        # if one file -> send directly; if many -> show list buttons (latest 10)
        if len(files) == 1:
            fpath = files[0]
            await context.bot.send_document(chat_id=query.message.chat_id, document=InputFile(str(fpath)), caption=f"{CATEGORIES.get(cat)}")
            await query.edit_message_text("Main menu:", reply_markup=build_main_menu())
            return
        # multiple files: build buttons
        kb = []
        for f in files[:10]:
            token = safe_encode_filename(f.name)
            kb.append([InlineKeyboardButton(f.name if len(f.name) <= 30 else f.name[:27] + "...", callback_data=f"getfile:{cat}:{token}")])
        kb.append([InlineKeyboardButton("🔙 Back", callback_data="back_main")])
        await query.edit_message_text(f"Select a file from {CATEGORIES.get(cat)}:", reply_markup=InlineKeyboardMarkup(kb))
        return

    # user requested specific file -> send it
    if data.startswith("getfile:"):
        parts = data.split(":", 2)
        if len(parts) < 3:
            await query.edit_message_text("Invalid file request.", reply_markup=build_main_menu())
            return
        cat, token = parts[1], parts[2]
        fname = safe_decode_filename(token)
        fpath = category_folder(cat) / fname
        if not fpath.exists():
            await query.edit_message_text("File not found (maybe expired).", reply_markup=build_main_menu())
            return
        await context.bot.send_document(chat_id=query.message.chat_id, document=InputFile(str(fpath)), caption=f"{CATEGORIES.get(cat)}")
        await query.edit_message_text("Main menu:", reply_markup=build_main_menu())
        return

    # Default
    await query.edit_message_text("Unknown action.", reply_markup=build_main_menu())


async def message_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    # Admin upload flow
    uid = update.effective_user.id
    # handle admin upload
    if uid in upload_state:
        cat = upload_state.pop(uid)
        # expect document
        doc = update.message.document
        if not doc:
            return await update.message.reply_text("Please send a document file to upload.")
        fname = doc.file_name or doc.file_id
        safe = "".join(c for c in fname if c.isalnum() or c in "._- ")
        out = category_folder(cat) / safe
        try:
            tgfile = await context.bot.get_file(doc.file_id)
            await tgfile.download_to_drive(str(out))
        except Exception:
            logger.exception("download failed")
            return await update.message.reply_text("Failed to download file.")
        # parse expiry from caption optional
        caption = (update.message.caption or "").strip()
        expiry_days = 0
        if caption.lower().startswith("expiry:"):
            try:
                expiry_days = int(caption.split(":", 1)[1].strip())
            except:
                expiry_days = 0
        meta = load_metadata(cat)
        expiry_ts = int(time.time()) + expiry_days * 86400 if expiry_days else 0
        meta[out.name] = {"uploaded_at": int(time.time()), "expiry_ts": expiry_ts}
        save_metadata(cat, meta)
        await update.message.reply_text(f"Uploaded {out.name} to {cat}. Expiry days: {expiry_days}")
        return

    # admin broadcast states
    if uid in broadcast_state:
        state = broadcast_state.pop(uid)
        mode = state.get("mode")
        # text broadcast
        if mode == "await_text":
            text = update.message.text or ""
            if not text:
                return await update.message.reply_text("Send text message to broadcast.")
            users = get_all_users()
            await update.message.reply_text(f"Broadcasting to {len(users)} users...")
            sent = failed = 0
            for s in users:
                try:
                    await context.bot.send_message(int(s), text)
                    sent += 1
                except Exception:
                    failed += 1
                await asyncio.sleep(DELAY_BETWEEN)
            return await update.message.reply_text(f"Broadcast done. Sent {sent}, Failed {failed}")
        # media broadcast
        if mode == "await_media":
            # accept photo or document
            if update.message.photo:
                file_id = update.message.photo[-1].file_id
                caption = update.message.caption or ""
                users = get_all_users()
                await update.message.reply_text(f"Broadcasting photo to {len(users)} users...")
                sent = failed = 0
                for s in users:
                    try:
                        await context.bot.send_photo(int(s), file_id, caption=caption)
                        sent += 1
                    except Exception:
                        failed += 1
                    await asyncio.sleep(DELAY_BETWEEN)
                return await update.message.reply_text(f"Broadcast done. Sent {sent}, Failed {failed}")
            elif update.message.document:
                file_id = update.message.document.file_id
                caption = update.message.caption or ""
                users = get_all_users()
                await update.message.reply_text(f"Broadcasting document to {len(users)} users...")
                sent = failed = 0
                for s in users:
                    try:
                        await context.bot.send_document(int(s), file_id, caption=caption)
                        sent += 1
                    except Exception:
                        failed += 1
                    await asyncio.sleep(DELAY_BETWEEN)
                return await update.message.reply_text(f"Broadcast done. Sent {sent}, Failed {failed}")
            else:
                return await update.message.reply_text("Please send a photo or document.")
    # If not admin flows, ignore or handle other messages
    # Allow admin commands via plain text: /broadcast <text> handled by command handler
    return


# ---------------------------
# Commands
# ---------------------------
async def adminlogin_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    # /adminlogin <pin>
    uid = update.effective_user.id
    if len(context.args) != 1:
        return await update.message.reply_text("Usage: /adminlogin <PIN>")
    pin = context.args[0].strip()
    if pin == ADMIN_PIN:
        start_admin_session(uid, minutes=120)  # session valid 120 min
        return await update.message.reply_text("Admin login successful. Use Admin Panel button or /adminpanel")
    return await update.message.reply_text("Invalid PIN.")


async def adminpanel_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    if not is_admin_session(uid):
        return await update.message.reply_text("Admin session required. Use /adminlogin <PIN>")
    kb = [
        [InlineKeyboardButton("Upload File", callback_data="admin_upload")],
        [InlineKeyboardButton("List Files", callback_data="admin_listfiles"),
         InlineKeyboardButton("Stats", callback_data="admin_stats")],
        [InlineKeyboardButton("Broadcast Text", callback_data="admin_broadcast_text"),
         InlineKeyboardButton("Broadcast Media", callback_data="admin_broadcast_media")],
    ]
    await update.message.reply_text("Admin Panel", reply_markup=InlineKeyboardMarkup(kb))


async def broadcast_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    if not is_admin_session(uid):
        return await update.message.reply_text("Admin only.")
    if not context.args:
        return await update.message.reply_text("Usage: /broadcast your message here")
    text = " ".join(context.args)
    users = get_all_users()
    await update.message.reply_text(f"Broadcasting to {len(users)} users...")
    sent = failed = 0
    for s in users:
        try:
            await context.bot.send_message(int(s), text)
            sent += 1
        except Exception:
            failed += 1
        await asyncio.sleep(DELAY_BETWEEN)
    await update.message.reply_text(f"Done. Sent {sent}, Failed {failed}")


async def broadcast_startphoto_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    if not is_admin_session(uid):
        return await update.message.reply_text("Admin only.")
    broadcast_state[uid] = {"mode": "await_media"}
    await update.message.reply_text("Send the photo/document to broadcast (with optional caption).")


async def broadcast_cancel_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    if uid in broadcast_state:
        broadcast_state.pop(uid, None)
        return await update.message.reply_text("Broadcast cancelled.")
    return await update.message.reply_text("No active broadcast.")


async def listfiles_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    # show files per category quick summary + option to view
    text_lines = []
    for k, label in CATEGORIES.items():
        files = list_category_files(k)
        text_lines.append(f"{label}: {len(files)} file(s)")
    await update.message.reply_text("Files:\n" + "\n".join(text_lines))


async def me_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = str(update.effective_user.id)
    users = json.loads(USERS_JSON.read_text())
    info = users.get(uid, {})
    uname = info.get("username", "")
    first = info.get("first_seen")
    first_str = datetime.utcfromtimestamp(first).strftime("%Y-%m-%d %H:%M UTC") if first else "n/a"
    await update.message.reply_text(f"👤 Profile\nID: `{uid}`\nUsername: @{uname}\nFirst seen: {first_str}", parse_mode="Markdown")


# ---------------------------
# Main / Setup
# ---------------------------
def main():
    if not BOT_TOKEN:
        print("Please set BOT_TOKEN env var")
        return

    app = ApplicationBuilder().token(BOT_TOKEN).build()

    # commands
    app.add_handler(CommandHandler("start", start_cmd))
    app.add_handler(CommandHandler("adminlogin", adminlogin_cmd))
    app.add_handler(CommandHandler("adminpanel", adminpanel_cmd))
    app.add_handler(CommandHandler("broadcast", broadcast_cmd))
    app.add_handler(CommandHandler("broadcast_startphoto", broadcast_startphoto_cmd))
    app.add_handler(CommandHandler("broadcast_cancel", broadcast_cancel_cmd))
    app.add_handler(CommandHandler("listfiles", listfiles_cmd))
    app.add_handler(CommandHandler("me", me_cmd))

    # callback queries
    app.add_handler(CallbackQueryHandler(callback_query_handler))

    # message handler for uploads & admin broadcast media flows
    app.add_handler(MessageHandler((filters.Document.ALL | filters.PHOTO) & filters.ChatType.PRIVATE, message_handler))
    # allow text for admin broadcast text when waiting
    app.add_handler(MessageHandler(filters.TEXT & filters.ChatType.PRIVATE, message_handler))

    # start cleanup background task once running
    async def on_startup(app):
        app.create_task(cleanup_expired_loop(app))

    app.post_init = on_startup

    print("Bot running...")
    app.run_polling()


if __name__ == "__main__":
    main()
