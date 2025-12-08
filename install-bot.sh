#!/bin/bash
# Telegram Bot Installer for Ubuntu 20.04-24.04
# Created by JVPN SHOP (modified)
# This installer writes a bot.py with improved send logic and persistent menu

clear
echo "=========================================="
echo "Telegram Bot Installer"
echo "Ubuntu 20.04 to 24.04"
echo "=========================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() {
    echo -e "${2}${1}${NC}"
}

if [ "$EUID" -eq 0 ]; then
    print_color "Error: Please do not run as root/sudo!" "$RED"
    print_color "Run as normal user: bash <(curl -Ls https://raw.githubusercontent.com/JVPNSHOP/Telegram/main/install-bot.sh)" "$YELLOW"
    exit 1
fi

print_color "Checking Ubuntu version..." "$BLUE"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    UBUNTU_VERSION=$VERSION_ID
    print_color "✓ Ubuntu $UBUNTU_VERSION detected" "$GREEN"
    if [[ "$UBUNTU_VERSION" != "20.04" && "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ]]; then
        print_color "Warning: This script is tested for Ubuntu 20.04, 22.04, 24.04" "$YELLOW"
        print_color "Your version: $UBUNTU_VERSION" "$YELLOW"
        read -p "Continue anyway? (y/n): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    print_color "Warning: Not Ubuntu system" "$YELLOW"
fi

get_bot_token() {
    echo ""
    print_color "===============================" "$BLUE"
    print_color "STEP 1: Bot Token Setup" "$BLUE"
    print_color "===============================" "$BLUE"
    echo ""

    print_color "How to get Bot Token:" "$YELLOW"
    echo "1. Open Telegram"
    echo "2. Search for @BotFather"
    echo "3. Send: /newbot"
    echo "4. Follow instructions"
    echo "5. Copy the token (looks like: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz)"
    echo ""

    while true; do
        read -p "Enter your Bot Token: " BOT_TOKEN
        if [ -z "$BOT_TOKEN" ]; then
            print_color "Bot Token is required!" "$RED"
        else
            print_color "✓ Bot Token accepted!" "$GREEN"
            break
        fi
    done
}

get_admin_id() {
    echo ""
    print_color "===============================" "$BLUE"
    print_color "STEP 2: Admin ID Setup" "$BLUE"
    print_color "===============================" "$BLUE"
    echo ""

    print_color "How to get your Telegram User ID:" "$YELLOW"
    echo "1. Open Telegram"
    echo "2. Search for @userinfobot"
    echo "3. Send: /start"
    echo "4. Copy your numeric ID (e.g., 123456789)"
    echo ""

    while true; do
        read -p "Enter your Admin ID: " ADMIN_ID
        if [ -z "$ADMIN_ID" ]; then
            print_color "Admin ID is required!" "$RED"
        elif ! [[ "$ADMIN_ID" =~ ^[0-9]+$ ]]; then
            print_color "Admin ID must contain only numbers!" "$RED"
        else
            print_color "✓ Admin ID accepted!" "$GREEN"
            break
        fi
    done
}

get_additional_admins() {
    echo ""
    read -p "Do you want to add more admins? (y/n): " add_more
    ADDITIONAL_ADMINS=""

    if [[ "$add_more" =~ ^[Yy]$ ]]; then
        echo ""
        print_color "Enter additional Admin IDs (press Enter to skip)" "$YELLOW"
        count=1
        while true; do
            read -p "Admin ID #$count (or press Enter to finish): " admin_id
            if [ -z "$admin_id" ]; then
                break
            fi
            if [[ "$admin_id" =~ ^[0-9]+$ ]]; then
                if [ -n "$ADDITIONAL_ADMINS" ]; then
                    ADDITIONAL_ADMINS="$ADDITIONAL_ADMINS,$admin_id"
                else
                    ADDITIONAL_ADMINS="$admin_id"
                fi
                print_color "✓ Added Admin ID: $admin_id" "$GREEN"
                ((count++))
            else
                print_color "Invalid ID. Numbers only!" "$RED"
            fi
        done
    fi

    if [ -n "$ADDITIONAL_ADMINS" ]; then
        ALL_ADMINS="$ADMIN_ID,$ADDITIONAL_ADMINS"
    else
        ALL_ADMINS="$ADMIN_ID"
    fi
}

confirm_settings() {
    clear
    print_color "==========================================" "$BLUE"
    print_color "SETTINGS CONFIRMATION" "$BLUE"
    print_color "==========================================" "$BLUE"
    echo ""

    print_color "Bot Token: ${BOT_TOKEN:0:15}..." "$GREEN"
    print_color "Main Admin ID: $ADMIN_ID" "$GREEN"
    if [ -n "$ADDITIONAL_ADMINS" ]; then
        print_color "Additional Admins: $ADDITIONAL_ADMINS" "$GREEN"
    fi

    echo ""
    print_color "Installation directory: ~/telegram-bot" "$YELLOW"
    echo ""

    read -p "Are these settings correct? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_color "Setup cancelled." "$RED"
        exit 0
    fi
}

install_dependencies() {
    print_color "Updating system packages..." "$BLUE"
    sudo apt update -y
    sudo apt upgrade -y

    print_color "Installing dependencies..." "$BLUE"
    sudo apt install -y python3 python3-pip python3-venv git sqlite3 tmux curl wget
}

setup_project() {
    print_color "Setting up project..." "$BLUE"

    cd ~
    if [ -d "telegram-bot" ]; then
        print_color "Backing up old bot..." "$YELLOW"
        mv telegram-bot telegram-bot-backup-$(date +%Y%m%d-%H%M%S)
    fi

    mkdir -p telegram-bot
    cd telegram-bot

    print_color "Creating Python virtual environment..." "$BLUE"
    python3 -m venv venv
    source venv/bin/activate

    print_color "Installing Python packages..." "$BLUE"
    pip install --upgrade pip
    pip install python-telegram-bot==20.7 python-dotenv==1.0.0

    mkdir -p data/files
}

create_env_file() {
    print_color "Creating configuration file..." "$BLUE"

    cat > .env << EOF
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
ADMIN_IDS=$ALL_ADMINS
EOF

    print_color "✓ .env file created" "$GREEN"
}

create_bot_file() {
    print_color "Creating bot.py..." "$BLUE"

    cat > bot.py << 'EOF'
import os
import logging
import sqlite3
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, BotCommand
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    MessageHandler,
    filters,
    ContextTypes,
    ConversationHandler
)
from dotenv import load_dotenv
from telegram.error import BadRequest

load_dotenv()

TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')
ADMIN_IDS = list(map(int, os.getenv('ADMIN_IDS', '').split(','))) if os.getenv('ADMIN_IDS') else []

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

os.makedirs('data/files', exist_ok=True)

(UPLOAD_CATEGORY, UPLOAD_SUBCATEGORY, UPLOAD_FILE, UPLOAD_CAPTION,
 UPLOAD_TEXT, GET_TEXT_TITLE, GET_TEXT_CONTENT,
 DELETE_FILE, CONFIRM_DELETE) = range(9)

def init_database():
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    # Add file_type column to support correct sending later (if not exists)
    c.execute('''
        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT,
            file_id TEXT,
            caption TEXT,
            category TEXT,
            subcategory TEXT,
            file_type TEXT DEFAULT '',
            uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS texts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            content TEXT,
            category TEXT,
            subcategory TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()

def main_menu_keyboard():
    keyboard = [
        [InlineKeyboardButton("📡 DTAC", callback_data='dtac')],
        [InlineKeyboardButton("📶 TRUE", callback_data='true')],
        [InlineKeyboardButton("🌐 AIS", callback_data='ais')],
        [InlineKeyboardButton("⚡ ATOM", callback_data='atom')],
        [InlineKeyboardButton("💰 DONATE", callback_data='donate')],
        [InlineKeyboardButton("⚙️ ADMIN PANEL", callback_data='admin_panel')]
    ]
    return InlineKeyboardMarkup(keyboard)

def dtac_menu_keyboard():
    keyboard = [
        [InlineKeyboardButton("DTAC ZIVPN", callback_data='dtac_zivpn')],
        [InlineKeyboardButton("DTAC GAMING", callback_data='dtac_gaming')],
        [InlineKeyboardButton("DTAC NOPRO", callback_data='dtac_nopro')],
        [InlineKeyboardButton("⬅️ Back to Main Menu", callback_data='main_menu')]
    ]
    return InlineKeyboardMarkup(keyboard)

def true_menu_keyboard():
    keyboard = [
        [InlineKeyboardButton("TRUE TWITTER", callback_data='true_twitter')],
        [InlineKeyboardButton("TRUE VDO", callback_data='true_vdo')],
        [InlineKeyboardButton("⬅️ Back to Main Menu", callback_data='main_menu')]
    ]
    return InlineKeyboardMarkup(keyboard)

def ais_menu_keyboard():
    keyboard = [
        [InlineKeyboardButton("AIS 64 KBPS", callback_data='ais_64kbps')],
        [InlineKeyboardButton("⬅️ Back to Main Menu", callback_data='main_menu')]
    ]
    return InlineKeyboardMarkup(keyboard)

def atom_menu_keyboard():
    keyboard = [
        [InlineKeyboardButton("ATOM 500 MB DAILY", callback_data='atom_500mb')],
        [InlineKeyboardButton("⬅️ Back to Main Menu", callback_data='main_menu')]
    ]
    return InlineKeyboardMarkup(keyboard)

def admin_panel_keyboard():
    keyboard = [
        [InlineKeyboardButton("📤 Upload File", callback_data='upload_file')],
        [InlineKeyboardButton("📝 Upload Text", callback_data='upload_text')],
        [InlineKeyboardButton("🗑️ Delete File", callback_data='delete_file')],
        [InlineKeyboardButton("📋 List Files", callback_data='list_files')],
        [InlineKeyboardButton("⬅️ Back to Main Menu", callback_data='main_menu')]
    ]
    return InlineKeyboardMarkup(keyboard)

def upload_category_keyboard():
    keyboard = [
        [InlineKeyboardButton("📡 DTAC", callback_data='upload_category_dtac')],
        [InlineKeyboardButton("📶 TRUE", callback_data='upload_category_true')],
        [InlineKeyboardButton("🌐 AIS", callback_data='upload_category_ais')],
        [InlineKeyboardButton("⚡ ATOM", callback_data='upload_category_atom')],
        [InlineKeyboardButton("❌ Cancel", callback_data='admin_panel')]
    ]
    return InlineKeyboardMarkup(keyboard)

def upload_dtac_subcategory_keyboard():
    keyboard = [
        [InlineKeyboardButton("DTAC ZIVPN", callback_data='upload_subcategory_dtac_zivpn')],
        [InlineKeyboardButton("DTAC GAMING", callback_data='upload_subcategory_dtac_gaming')],
        [InlineKeyboardButton("DTAC NOPRO", callback_data='upload_subcategory_dtac_nopro')],
        [InlineKeyboardButton("⬅️ Back to Categories", callback_data='upload_file')],
        [InlineKeyboardButton("❌ Cancel", callback_data='admin_panel')]
    ]
    return InlineKeyboardMarkup(keyboard)

def donate_menu():
    return """ 💳 **Donation Information**  **True Money Wallet:** 📱 0953244179  **Bank Transfer:** 🏦 KBZ Bank 💰 1234 5678 9012 📛 Your Name  Thank you for your support! 🙏 """

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    welcome_message = """ 👋 Welcome to Myanmar VPN Bot!  Please select from the menu below: """
    if update.message:
        await update.message.reply_text(
            welcome_message,
            reply_markup=main_menu_keyboard(),
            parse_mode='Markdown'
        )
    elif update.callback_query:
        await update.callback_query.edit_message_text(
            welcome_message,
            reply_markup=main_menu_keyboard(),
            parse_mode='Markdown'
        )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    help_text = """ 🤖 **Bot Commands:** /start - Start the bot /help - Show this help message /menu - Show main menu  📱 **Contact Admin:** @your_admin_username """
    if update.message:
        await update.message.reply_text(help_text, parse_mode='Markdown')
    else:
        await update.callback_query.edit_message_text(help_text, parse_mode='Markdown')

async def menu_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.message:
        await update.message.reply_text(
            "📱 **Main Menu**\n\nPlease select an option:",
            reply_markup=main_menu_keyboard(),
            parse_mode='Markdown'
        )
    elif update.callback_query:
        await update.callback_query.edit_message_text(
            "📱 **Main Menu**\n\nPlease select an option:",
            reply_markup=main_menu_keyboard(),
            parse_mode='Markdown'
        )

async def admin_panel_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!", reply_markup=main_menu_keyboard())
        return ConversationHandler.END
    await query.edit_message_text("🔧 **Admin Panel**\n\nSelect an option:", reply_markup=admin_panel_keyboard(), parse_mode='Markdown')
    return ConversationHandler.END

async def upload_file_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!")
        return ConversationHandler.END
    context.user_data.clear()
    await query.edit_message_text("📤 **Upload File**\n\nSelect category for this file:", reply_markup=upload_category_keyboard(), parse_mode='Markdown')
    return UPLOAD_CATEGORY

async def select_upload_category(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!")
        return ConversationHandler.END
    category = query.data.replace('upload_category_', '')
    context.user_data['upload_category'] = category
    if category == 'dtac':
        await query.edit_message_text("📤 **Upload File** → 📡 **DTAC**\n\nSelect subcategory:", reply_markup=upload_dtac_subcategory_keyboard(), parse_mode='Markdown')
    else:
        await query.edit_message_text("📤 **Upload File**\n\nSelect subcategory:", reply_markup=upload_category_keyboard(), parse_mode='Markdown')
    return UPLOAD_SUBCATEGORY

async def select_upload_subcategory(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!")
        return ConversationHandler.END
    subcategory = query.data.replace('upload_subcategory_', '')
    context.user_data['upload_subcategory'] = subcategory
    await query.edit_message_text(
        f"📤 **Upload File**\n\n✅ Category: {context.user_data.get('upload_category', 'N/A')}\n"
        f"✅ Subcategory: {subcategory}\n\n"
        "Now please send me the file (document, photo, video, or audio):\n\n"
        "Type /cancel to cancel.",
        parse_mode='Markdown'
    )
    return UPLOAD_FILE

async def handle_file_upload(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await update.message.reply_text("⛔ Access denied!")
        return ConversationHandler.END

    # Determine file and type
    file_type = ''
    file_obj = None
    if update.message.document:
        file_obj = update.message.document
        file_type = 'document'
    elif update.message.photo:
        file_obj = update.message.photo[-1]
        file_type = 'photo'
    elif update.message.video:
        file_obj = update.message.video
        file_type = 'video'
    elif update.message.audio:
        file_obj = update.message.audio
        file_type = 'audio'
    else:
        await update.message.reply_text("Please send a valid file!")
        return UPLOAD_FILE

    file_id = file_obj.file_id
    file_name = getattr(file_obj, 'file_name', None) or f"{file_type}_{file_id}"

    context.user_data['file_id'] = file_id
    context.user_data['file_name'] = file_name
    context.user_data['file_type'] = file_type

    await update.message.reply_text(
        f"✅ File received!\n\n📄 **Filename:** {file_name}\n"
        f"📦 **Type:** {file_type}\n\n"
        "Now please send a caption for this file (or type /skip to skip):",
        parse_mode='Markdown'
    )
    return UPLOAD_CAPTION

async def handle_file_caption(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await update.message.reply_text("⛔ Access denied!")
        return ConversationHandler.END

    caption = update.message.text or ''
    file_id = context.user_data.get('file_id')
    file_name = context.user_data.get('file_name')
    category = context.user_data.get('upload_category')
    subcategory = context.user_data.get('upload_subcategory')
    file_type = context.user_data.get('file_type', '')

    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute(
        "INSERT INTO files (filename, file_id, caption, category, subcategory, file_type) VALUES (?, ?, ?, ?, ?, ?)",
        (file_name, file_id, caption, category, subcategory, file_type)
    )
    conn.commit()
    conn.close()

    context.user_data.clear()

    await update.message.reply_text(
        f"✅ File uploaded successfully!\n\n"
        f"📁 **Category:** {category.upper()}\n"
        f"📂 **Subcategory:** {subcategory.replace('_', ' ').upper()}\n"
        f"📄 **Filename:** {file_name}\n"
        f"📝 **Caption:** {caption[:100] if caption else 'No caption'}",
        reply_markup=admin_panel_keyboard(),
        parse_mode='Markdown'
    )
    return ConversationHandler.END

async def skip_caption(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await update.message.reply_text("⛔ Access denied!")
        return ConversationHandler.END

    file_id = context.user_data.get('file_id')
    file_name = context.user_data.get('file_name')
    category = context.user_data.get('upload_category')
    subcategory = context.user_data.get('upload_subcategory')
    file_type = context.user_data.get('file_type', '')

    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute(
        "INSERT INTO files (filename, file_id, caption, category, subcategory, file_type) VALUES (?, ?, ?, ?, ?, ?)",
        (file_name, file_id, '', category, subcategory, file_type)
    )
    conn.commit()
    conn.close()

    context.user_data.clear()

    await update.message.reply_text(
        f"✅ File uploaded successfully!\n\n"
        f"📁 **Category:** {category.upper()}\n"
        f"📂 **Subcategory:** {subcategory.replace('_', ' ').upper()}\n"
        f"📄 **Filename:** {file_name}",
        reply_markup=admin_panel_keyboard(),
        parse_mode='Markdown'
    )
    return ConversationHandler.END

async def upload_text_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!")
        return ConversationHandler.END
    context.user_data.clear()
    await query.edit_message_text("📝 **Upload Text**\n\nSelect category for this text:", reply_markup=upload_category_keyboard(), parse_mode='Markdown')
    return UPLOAD_CATEGORY

async def get_text_category(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!")
        return ConversationHandler.END
    category = query.data.replace('upload_category_', '')
    context.user_data['text_category'] = category
    await query.edit_message_text(f"📝 **Upload Text** → {category.upper()}\n\nPlease enter the title for your text:\n\nType /cancel to cancel.", parse_mode='Markdown')
    return GET_TEXT_TITLE

async def get_text_title(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await update.message.reply_text("⛔ Access denied!")
        return ConversationHandler.END
    context.user_data['text_title'] = update.message.text
    await update.message.reply_text("📝 Now please enter the content for your text:\n\nType /cancel to cancel.", parse_mode='Markdown')
    return GET_TEXT_CONTENT

async def get_text_content(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await update.message.reply_text("⛔ Access denied!")
        return ConversationHandler.END
    title = context.user_data.get('text_title', '')
    content = update.message.text
    category = context.user_data.get('text_category', '')
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute("INSERT INTO texts (title, content, category) VALUES (?, ?, ?)", (title, content, category))
    conn.commit()
    conn.close()
    context.user_data.clear()
    await update.message.reply_text(f"✅ Text saved successfully!\n\n📁 **Category:** {category.upper()}\n📌 **Title:** {title}\n📄 **Content:** {content[:100]}...", reply_markup=admin_panel_keyboard(), parse_mode='Markdown')
    return ConversationHandler.END

async def list_files_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!")
        return
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute("SELECT id, filename, category, subcategory FROM files ORDER BY uploaded_at DESC LIMIT 20")
    files = c.fetchall()
    c.execute("SELECT id, title, category FROM texts ORDER BY created_at DESC LIMIT 20")
    texts = c.fetchall()
    conn.close()
    message = "📋 **Stored Files & Texts**\n\n"
    if files:
        message += "📁 **Files:**\n"
        for file_id, filename, category, subcategory in files:
            message += f"• `{filename}`\n  📁 {category.upper()} → {subcategory.replace('_', ' ').upper()} (ID: `{file_id}`)\n"
    else:
        message += "📁 No files uploaded yet.\n"
    message += "\n📝 **Texts:**\n"
    if texts:
        for text_id, title, category in texts:
            message += f"• `{title}`\n  📁 {category.upper()} (ID: `{text_id}`)\n"
    else:
        message += "No texts uploaded yet.\n"
    message += "\n**Commands:**\n"
    message += "• `/sendfile [ID]` - Send a file\n"
    message += "• `/sendtext [ID]` - Send text\n"
    message += "• `/deletefile [ID]` - Delete a file\n"
    await query.edit_message_text(message, parse_mode='Markdown', reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("⬅️ Back to Admin Panel", callback_data='admin_panel')]]))

async def delete_file_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!")
        return ConversationHandler.END
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute("SELECT id, filename, category, subcategory FROM files ORDER BY uploaded_at DESC")
    files = c.fetchall()
    conn.close()
    if not files:
        await query.edit_message_text("No files to delete!", reply_markup=admin_panel_keyboard())
        return ConversationHandler.END
    keyboard = []
    for file in files:
        file_id, filename, category, subcategory = file
        keyboard.append([InlineKeyboardButton(f"🗑️ {filename[:20]}... ({category}/{subcategory})", callback_data=f'delete_{file_id}')])
    keyboard.append([InlineKeyboardButton("⬅️ Back to Admin Panel", callback_data='admin_panel')])
    await query.edit_message_text("🗑️ **Delete File**\n\nSelect a file to delete:", reply_markup=InlineKeyboardMarkup(keyboard), parse_mode='Markdown')
    return DELETE_FILE

async def confirm_delete(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!")
        return ConversationHandler.END
    file_id = int(query.data.split('_')[1])
    context.user_data['delete_file_id'] = file_id
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute("SELECT filename, category, subcategory FROM files WHERE id = ?", (file_id,))
    result = c.fetchone()
    conn.close()
    if result:
        filename, category, subcategory = result
        await query.edit_message_text(
            f"⚠️ **Confirm Delete**\n\n"
            f"Are you sure you want to delete:\n"
            f"📄 **File:** `{filename}`\n"
            f"📁 **Category:** {category.upper()}\n"
            f"📂 **Subcategory:** {subcategory.replace('_', ' ').upper()}\n\n"
            f"**This action cannot be undone!**",
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("✅ Yes, Delete", callback_data='confirm_delete_yes')],
                [InlineKeyboardButton("❌ Cancel", callback_data='admin_panel')]
            ])
        )
        return CONFIRM_DELETE
    await query.edit_message_text("File not found!", reply_markup=admin_panel_keyboard())
    return ConversationHandler.END

async def execute_delete(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!")
        return ConversationHandler.END
    file_id = context.user_data.get('delete_file_id')
    if file_id:
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("DELETE FROM files WHERE id = ?", (file_id,))
        conn.commit()
        conn.close()
        await query.edit_message_text("✅ File deleted successfully!", reply_markup=admin_panel_keyboard())
    else:
        await query.edit_message_text("Error deleting file!", reply_markup=admin_panel_keyboard())
    return ConversationHandler.END

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        return ConversationHandler.END
    await update.message.reply_text("Operation cancelled.", reply_markup=admin_panel_keyboard())
    return ConversationHandler.END

async def send_file_by_id(chat_id, file_id, caption, context):
    # Try document first, if fails, try photo/video/audio.
    try:
        await context.bot.send_document(chat_id=chat_id, document=file_id, caption=caption or "Here is your file!", parse_mode='Markdown')
        return True
    except BadRequest as e:
        # try photo
        try:
            await context.bot.send_photo(chat_id=chat_id, photo=file_id, caption=caption or "Here is your file!", parse_mode='Markdown')
            return True
        except BadRequest:
            try:
                await context.bot.send_video(chat_id=chat_id, video=file_id, caption=caption or "Here is your file!", parse_mode='Markdown')
                return True
            except BadRequest:
                try:
                    await context.bot.send_audio(chat_id=chat_id, audio=file_id, caption=caption or "Here is your file!", parse_mode='Markdown')
                    return True
                except Exception as err:
                    logger.error(f"All sends failed for file_id {file_id}: {err}")
                    return False
    except Exception as e:
        logger.error(f"Unexpected error sending file: {e}")
        return False

async def send_file_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.args:
        await update.message.reply_text("Usage: /sendfile [file_id]\n\nGet file IDs from /listfiles")
        return
    try:
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("SELECT file_id, caption FROM files WHERE id = ?", (int(context.args[0]),))
        result = c.fetchone()
        conn.close()
        if result:
            file_id_db, caption = result
            ok = await send_file_by_id(update.effective_chat.id, file_id_db, caption, context)
            if not ok:
                await update.message.reply_text("Error sending file (unsupported type or Telegram error). Check logs.")
        else:
            await update.message.reply_text("File not found!")
    except Exception as e:
        logger.error(f"Error sending file: {e}")
        await update.message.reply_text("Error sending file!")

async def send_text_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.args:
        await update.message.reply_text("Usage: /sendtext [text_id]\n\nGet text IDs from /listfiles")
        return
    try:
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("SELECT title, content FROM texts WHERE id = ?", (int(context.args[0]),))
        result = c.fetchone()
        conn.close()
        if result:
            title, content = result
            await update.message.reply_text(f"📌 **{title}**\n\n{content}", parse_mode='Markdown')
        else:
            await update.message.reply_text("Text not found!")
    except Exception as e:
        logger.error(f"Error sending text: {e}")
        await update.message.reply_text("Error sending text!")

async def list_files_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await update.message.reply_text("⛔ Access denied!")
        return
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute("SELECT id, filename, category, subcategory FROM files ORDER BY uploaded_at DESC")
    files = c.fetchall()
    conn.close()
    if not files:
        await update.message.reply_text("No files uploaded yet!")
        return
    message = "📋 **All Files:**\n\n"
    for file_id, filename, category, subcategory in files:
        message += f"• `{filename}`\n  📁 {category.upper()} → {subcategory.replace('_', ' ').upper()} (ID: `{file_id}`)\n"
    message += "\n**Commands:**\n"
    message += "• `/sendfile [ID]` - Send a file\n"
    message += "• `/deletefile [ID]` - Delete a file"
    await update.message.reply_text(message, parse_mode='Markdown')

async def delete_file_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await update.message.reply_text("⛔ Access denied!")
        return
    if not context.args:
        await update.message.reply_text("Usage: /deletefile [file_id]\n\nGet file IDs from /listfiles")
        return
    try:
        file_id = int(context.args[0])
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("DELETE FROM files WHERE id = ?", (file_id,))
        conn.commit()
        conn.close()
        await update.message.reply_text(f"✅ File {file_id} deleted successfully!")
    except Exception as e:
        logger.error(f"Error deleting file: {e}")
        await update.message.reply_text("Error deleting file!")

async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    data = query.data

    if data == 'main_menu':
        await query.edit_message_text("📱 **Main Menu**\n\nPlease select an option:", reply_markup=main_menu_keyboard(), parse_mode='Markdown')
        return

    if data == 'dtac':
        await query.edit_message_text("📡 **DTAC Packages**\n\nPlease select an option:", reply_markup=dtac_menu_keyboard(), parse_mode='Markdown')
        return

    if data.startswith('dtac_'):
        sub = data  # e.g., 'dtac_zivpn'
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("SELECT file_id, caption FROM files WHERE category='dtac' AND subcategory=? ORDER BY uploaded_at DESC", (sub,))
        files = c.fetchall()
        conn.close()
        if files:
            for file_id, caption in files:
                await send_file_by_id(update.effective_chat.id, file_id, caption, context)
            await query.edit_message_text("Files sent.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("⬅️ Back to DTAC Menu", callback_data='dtac'), InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]]))
        else:
            await query.edit_message_text("No files available for this category yet.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("⬅️ Back to DTAC Menu", callback_data='dtac'), InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]]))
        return

    if data == 'true':
        await query.edit_message_text("📶 **TRUE Packages**\n\nPlease select an option:", reply_markup=true_menu_keyboard(), parse_mode='Markdown')
        return

    if data.startswith('true_'):
        sub = data
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("SELECT file_id, caption FROM files WHERE category='true' AND subcategory=? ORDER BY uploaded_at DESC", (sub,))
        files = c.fetchall()
        conn.close()
        if files:
            for file_id, caption in files:
                await send_file_by_id(update.effective_chat.id, file_id, caption, context)
            await query.edit_message_text("Files sent.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("⬅️ Back to TRUE Menu", callback_data='true'), InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]]))
        else:
            await query.edit_message_text("No files available for this category yet.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("⬅️ Back to TRUE Menu", callback_data='true'), InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]]))
        return

    if data == 'ais':
        await query.edit_message_text("🌐 **AIS Packages**\n\nPlease select an option:", reply_markup=ais_menu_keyboard(), parse_mode='Markdown')
        return

    if data == 'atom':
        await query.edit_message_text("⚡ **ATOM Packages**\n\nPlease select an option:", reply_markup=atom_menu_keyboard(), parse_mode='Markdown')
        return

    if data == 'donate':
        await query.edit_message_text(donate_menu(), parse_mode='Markdown', reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("⬅️ Back to Main Menu", callback_data='main_menu')]]))
        return

    if data == 'admin_panel':
        await admin_panel_start(update, context)
        return

    if data == 'upload_file':
        await upload_file_start(update, context)
        return

    if data == 'upload_text':
        await upload_text_start(update, context)
        return

    if data == 'delete_file':
        await delete_file_start(update, context)
        return

    if data == 'list_files':
        await list_files_callback(update, context)
        return

    if data.startswith('upload_category_'):
        await select_upload_category(update, context)
        return

    if data.startswith('upload_subcategory_'):
        await select_upload_subcategory(update, context)
        return

def build_app():
    init_database()
    app = Application.builder().token(TOKEN).build()

    # Command handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(CommandHandler("menu", menu_command))
    app.add_handler(CommandHandler("sendfile", send_file_command))
    app.add_handler(CommandHandler("sendtext", send_text_command))
    app.add_handler(CommandHandler("listfiles", list_files_command))
    app.add_handler(CommandHandler("deletefile", delete_file_command))

    # Conversation handlers (register first)
    upload_file_conversation = ConversationHandler(
        entry_points=[CallbackQueryHandler(upload_file_start, pattern='^upload_file$')],
        states={
            UPLOAD_CATEGORY: [CallbackQueryHandler(select_upload_category, pattern='^upload_category_')],
            UPLOAD_SUBCATEGORY: [CallbackQueryHandler(select_upload_subcategory, pattern='^upload_subcategory_')],
            UPLOAD_FILE: [MessageHandler(filters.Document.ALL | filters.PHOTO | filters.VIDEO | filters.AUDIO, handle_file_upload)],
            UPLOAD_CAPTION: [MessageHandler(filters.TEXT & ~filters.COMMAND, handle_file_caption), CommandHandler('skip', skip_caption)],
        },
        fallbacks=[CommandHandler('cancel', cancel), CallbackQueryHandler(admin_panel_start, pattern='^admin_panel$')],
    )

    upload_text_conversation = ConversationHandler(
        entry_points=[CallbackQueryHandler(upload_text_start, pattern='^upload_text$')],
        states={
            UPLOAD_CATEGORY: [CallbackQueryHandler(get_text_category, pattern='^upload_category_')],
            GET_TEXT_TITLE: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_text_title)],
            GET_TEXT_CONTENT: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_text_content)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
    )

    delete_conversation = ConversationHandler(
        entry_points=[CallbackQueryHandler(delete_file_start, pattern='^delete_file$'), CallbackQueryHandler(confirm_delete, pattern='^delete_')],
        states={
            DELETE_FILE: [CallbackQueryHandler(confirm_delete, pattern='^delete_')],
            CONFIRM_DELETE: [CallbackQueryHandler(execute_delete, pattern='^confirm_delete_yes$'), CallbackQueryHandler(admin_panel_start, pattern='^admin_panel$')],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
    )

    app.add_handler(upload_file_conversation)
    app.add_handler(upload_text_conversation)
    app.add_handler(delete_conversation)

    # Generic callback handler AFTER conversations
    app.add_handler(CallbackQueryHandler(button_handler))

    # Fallback: show menu on any plain message (so menu appears without /start)
    app.add_handler(MessageHandler(filters.ALL & ~filters.COMMAND, menu_command))

    # On startup: set bot commands so client menu shows
    async def on_startup(app):
        try:
            commands = [
                BotCommand("start", "Start the bot"),
                BotCommand("menu", "Show main menu"),
                BotCommand("help", "Show help"),
                BotCommand("listfiles", "List all files (admin)"),
            ]
            await app.bot.set_my_commands(commands)
        except Exception as e:
            logger.error(f"Failed to set commands: {e}")

    app.post_init.append(on_startup)
    return app

def main():
    if not TOKEN:
        print("Error: TELEGRAM_BOT_TOKEN not set in .env")
        return
    app = build_app()
    print("🤖 Bot is starting...")
    app.run_polling(allowed_updates=None)

if __name__ == '__main__':
    main()
EOF

    print_color "✓ bot.py created" "$GREEN"
}

create_run_scripts() {
    print_color "Creating run scripts..." "$BLUE"

    cat > run-bot.sh << 'EOF'
#!/bin/bash
cd ~/telegram-bot
source venv/bin/activate
python3 bot.py
EOF
    chmod +x run-bot.sh

    cat > start-bot.sh << 'EOF'
#!/bin/bash
cd ~/telegram-bot
if [ -f "bot.pid" ]; then
    echo "Bot is already running (PID: $(cat bot.pid))"
    exit 1
fi
source venv/bin/activate
nohup python3 bot.py > bot.log 2>&1 &
echo $! > bot.pid
echo "Bot started with PID: $!"
EOF
    chmod +x start-bot.sh

    cat > stop-bot.sh << 'EOF'
#!/bin/bash
cd ~/telegram-bot
if [ -f "bot.pid" ]; then
    pid=$(cat bot.pid)
    if kill -0 $pid 2>/dev/null; then
        kill $pid
        echo "Bot stopped (PID: $pid)"
        rm -f bot.pid
    else
        echo "Bot is not running"
        rm -f bot.pid
    fi
else
    echo "Bot is not running"
fi
EOF
    chmod +x stop-bot.sh

    cat > restart-bot.sh << 'EOF'
#!/bin/bash
cd ~/telegram-bot
./stop-bot.sh
sleep 2
./start-bot.sh
EOF
    chmod +x restart-bot.sh

    cat > update.sh << 'EOF'
#!/bin/bash
cd ~/telegram-bot
echo "Updating system packages..."
sudo apt update -y
sudo apt upgrade -y
echo "Updating Python packages..."
source venv/bin/activate
pip install --upgrade python-telegram-bot python-dotenv
echo "Restarting bot..."
./restart-bot.sh
EOF
    chmod +x update.sh
}

create_systemd_service() {
    print_color "Creating systemd service..." "$BLUE"

    cat > telegram-bot.service << EOF
[Unit]
Description=Telegram Bot Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/home/$USER/telegram-bot
Environment="PATH=/home/$USER/telegram-bot/venv/bin"
ExecStart=/home/$USER/telegram-bot/venv/bin/python3 bot.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    print_color "✓ systemd service file created" "$GREEN"
}

show_instructions() {
    clear
    print_color "INSTALLATION COMPLETE!" "$GREEN"
    echo ""
    print_color "Bot Directory: ~/telegram-bot" "$YELLOW"
    print_color "Config File: ~/telegram-bot/.env" "$YELLOW"
    print_color "Logs: ~/telegram-bot/bot.log" "$YELLOW"
    echo ""
    print_color "Start bot now? (y/n)" "$BLUE"
    read -p "Start now? (y/n): " start_now
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        cd ~/telegram-bot
        ./start-bot.sh
        sleep 2
        if [ -f "bot.pid" ]; then
            pid=$(cat bot.pid)
            if kill -0 $pid 2>/dev/null; then
                print_color "✓ Bot is running (PID: $pid)" "$GREEN"
            else
                print_color "✗ Bot failed to start. Check bot.log" "$RED"
            fi
        fi
    fi
    print_color "Done." "$GREEN"
}

main() {
    print_color "Starting installation..." "$GREEN"
    get_bot_token
    get_admin_id
    get_additional_admins
    confirm_settings

    install_dependencies
    setup_project
    create_env_file
    create_bot_file
    create_run_scripts
    create_systemd_service

    show_instructions
}

main
