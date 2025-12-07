#!/bin/bash
# Telegram Bot Installer for Ubuntu 20.04-24.04
# Created by JVPN SHOP
# GitHub: https://github.com/JVPNSHOP/Telegram

clear
echo "=========================================="
echo "Telegram Bot Installer"
echo "Ubuntu 20.04 to 24.04"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored text
print_color() {
    echo -e "${2}${1}${NC}"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_color "Error: Please do not run as root/sudo!" "$RED"
    print_color "Run as normal user: bash <(curl -Ls https://raw.githubusercontent.com/JVPNSHOP/Telegram/main/install-bot.sh)" "$YELLOW"
    exit 1
fi

# Check Ubuntu version
print_color "Checking Ubuntu version..." "$BLUE"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    UBUNTU_VERSION=$VERSION_ID
    print_color "✓ Ubuntu $UBUNTU_VERSION detected" "$GREEN"
    
    # Check if version is supported
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

# Function to get bot token
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
        elif [[ ! "$BOT_TOKEN" =~ ^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$ ]]; then
            print_color "Invalid Bot Token format!" "$RED"
            print_color "Example: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz" "$YELLOW"
        else
            print_color "✓ Bot Token accepted!" "$GREEN"
            break
        fi
    done
}

# Function to get admin ID
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

# Function to ask for more admins
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

# Function to confirm settings
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

# Function to install dependencies
install_dependencies() {
    print_color "Updating system packages..." "$BLUE"
    sudo apt update -y
    sudo apt upgrade -y
    
    print_color "Installing dependencies..." "$BLUE"
    sudo apt install -y python3 python3-pip python3-venv git sqlite3 tmux curl wget
}

# Function to setup project
setup_project() {
    print_color "Setting up project..." "$BLUE"
    
    cd ~
    if [ -d "telegram-bot" ]; then
        print_color "Backing up old bot..." "$YELLOW"
        mv telegram-bot telegram-bot-backup-$(date +%Y%m%d-%H%M%S)
    fi
    
    mkdir -p telegram-bot
    cd telegram-bot
    
    # Create virtual environment
    print_color "Creating Python virtual environment..." "$BLUE"
    python3 -m venv venv
    source venv/bin/activate
    
    # Install Python packages
    print_color "Installing Python packages..." "$BLUE"
    pip install --upgrade pip
    pip install python-telegram-bot==20.7 python-dotenv==1.0.0
    
    # Create directories
    mkdir -p data/files
}

# Function to create .env file
create_env_file() {
    print_color "Creating configuration file..." "$BLUE"
    
    cat > .env << EOF
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
ADMIN_IDS=$ALL_ADMINS
EOF
    
    print_color "✓ .env file created" "$GREEN"
}

# Function to create bot.py
create_bot_file() {
    print_color "Creating bot.py..." "$BLUE"
    
    cat > bot.py << 'EOF'
import os
import logging
import sqlite3
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
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

# Load environment variables
load_dotenv()

# Configuration
TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')
ADMIN_IDS = list(map(int, os.getenv('ADMIN_IDS', '').split(','))) if os.getenv('ADMIN_IDS') else []

# Enable logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# Create necessary directories
os.makedirs('data/files', exist_ok=True)

# ==================== CONVERSATION STATES ====================
(UPLOAD_CATEGORY, UPLOAD_SUBCATEGORY, UPLOAD_FILE, UPLOAD_CAPTION,
 UPLOAD_TEXT, GET_TEXT_TITLE, GET_TEXT_CONTENT,
 DELETE_FILE, CONFIRM_DELETE) = range(9)

# ==================== DATABASE FUNCTIONS ====================
def init_database():
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    
    c.execute('''
        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT,
            file_id TEXT,
            caption TEXT,
            category TEXT,
            subcategory TEXT,
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

# ==================== KEYBOARD FUNCTIONS ====================
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

def upload_true_subcategory_keyboard():
    keyboard = [
        [InlineKeyboardButton("TRUE TWITTER", callback_data='upload_subcategory_true_twitter')],
        [InlineKeyboardButton("TRUE VDO", callback_data='upload_subcategory_true_vdo')],
        [InlineKeyboardButton("⬅️ Back to Categories", callback_data='upload_file')],
        [InlineKeyboardButton("❌ Cancel", callback_data='admin_panel')]
    ]
    return InlineKeyboardMarkup(keyboard)

def upload_ais_subcategory_keyboard():
    keyboard = [
        [InlineKeyboardButton("AIS 64 KBPS", callback_data='upload_subcategory_ais_64kbps')],
        [InlineKeyboardButton("⬅️ Back to Categories", callback_data='upload_file')],
        [InlineKeyboardButton("❌ Cancel", callback_data='admin_panel')]
    ]
    return InlineKeyboardMarkup(keyboard)

def upload_atom_subcategory_keyboard():
    keyboard = [
        [InlineKeyboardButton("ATOM 500 MB DAILY", callback_data='upload_subcategory_atom_500mb')],
        [InlineKeyboardButton("⬅️ Back to Categories", callback_data='upload_file')],
        [InlineKeyboardButton("❌ Cancel", callback_data='admin_panel')]
    ]
    return InlineKeyboardMarkup(keyboard)

def file_list_keyboard(files):
    keyboard = []
    for file in files:
        keyboard.append([InlineKeyboardButton(f"🗑️ {file[1]}", callback_data=f'delete_{file[0]}')])
    keyboard.append([InlineKeyboardButton("⬅️ Back to Admin Panel", callback_data='admin_panel')])
    return InlineKeyboardMarkup(keyboard)

# ==================== DONATE FUNCTION ====================
def donate_menu():
    return """
💳 **Donation Information**

**True Money Wallet:**
📱 0953244179

**Bank Transfer:**
🏦 KBZ Bank
💰 1234 5678 9012
📛 Your Name

Thank you for your support! 🙏
"""

# ==================== BOT COMMANDS ====================
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    welcome_message = """
👋 Welcome to Myanmar VPN Bot!

Please select from the menu below:
"""
    await update.message.reply_text(
        welcome_message,
        reply_markup=main_menu_keyboard(),
        parse_mode='Markdown'
    )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    help_text = """
🤖 **Bot Commands:**
/start - Start the bot
/help - Show this help message
/menu - Show main menu

📱 **Contact Admin:**
@your_admin_username
"""
    await update.message.reply_text(help_text, parse_mode='Markdown')

async def menu_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "📱 **Main Menu**\n\nPlease select an option:",
        reply_markup=main_menu_keyboard(),
        parse_mode='Markdown'
    )

# ==================== ADMIN FUNCTIONS ====================
async def admin_panel_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text(
            "⛔ Access denied! You are not admin.",
            reply_markup=main_menu_keyboard()
        )
        return ConversationHandler.END
    
    await query.edit_message_text(
        "🔧 **Admin Panel**\n\nSelect an option:",
        reply_markup=admin_panel_keyboard(),
        parse_mode='Markdown'
    )
    return ConversationHandler.END

# ==================== UPLOAD FILE FLOW ====================
async def upload_file_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!")
        return ConversationHandler.END
    
    # Clear any existing data
    context.user_data.clear()
    
    await query.edit_message_text(
        "📤 **Upload File**\n\nSelect category for this file:",
        reply_markup=upload_category_keyboard(),
        parse_mode='Markdown'
    )
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
    
    # Show subcategory based on category
    if category == 'dtac':
        await query.edit_message_text(
            "📤 **Upload File** → 📡 **DTAC**\n\nSelect subcategory:",
            reply_markup=upload_dtac_subcategory_keyboard(),
            parse_mode='Markdown'
        )
    elif category == 'true':
        await query.edit_message_text(
            "📤 **Upload File** → 📶 **TRUE**\n\nSelect subcategory:",
            reply_markup=upload_true_subcategory_keyboard(),
            parse_mode='Markdown'
        )
    elif category == 'ais':
        await query.edit_message_text(
            "📤 **Upload File** → 🌐 **AIS**\n\nSelect subcategory:",
            reply_markup=upload_ais_subcategory_keyboard(),
            parse_mode='Markdown'
        )
    elif category == 'atom':
        await query.edit_message_text(
            "📤 **Upload File** → ⚡ **ATOM**\n\nSelect subcategory:",
            reply_markup=upload_atom_subcategory_keyboard(),
            parse_mode='Markdown'
        )
    
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
    
    # Get file
    if update.message.document:
        file = update.message.document
        file_type = "document"
    elif update.message.photo:
        file = update.message.photo[-1]
        file_type = "photo"
    elif update.message.video:
        file = update.message.video
        file_type = "video"
    elif update.message.audio:
        file = update.message.audio
        file_type = "audio"
    else:
        await update.message.reply_text("Please send a valid file!")
        return UPLOAD_FILE
    
    context.user_data['file_id'] = file.file_id
    context.user_data['file_name'] = file.file_name or f"{file_type}_{file.file_id}"
    context.user_data['file_type'] = file_type
    
    await update.message.reply_text(
        f"✅ File received!\n\n📄 **Filename:** {context.user_data['file_name']}\n"
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
    
    caption = update.message.text
    
    # Get data from context
    file_id = context.user_data.get('file_id')
    file_name = context.user_data.get('file_name')
    category = context.user_data.get('upload_category')
    subcategory = context.user_data.get('upload_subcategory')
    
    # Save to database
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute(
        "INSERT INTO files (filename, file_id, caption, category, subcategory) VALUES (?, ?, ?, ?, ?)",
        (file_name, file_id, caption, category, subcategory)
    )
    conn.commit()
    conn.close()
    
    # Clear user data
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
    
    # Get data from context
    file_id = context.user_data.get('file_id')
    file_name = context.user_data.get('file_name')
    category = context.user_data.get('upload_category')
    subcategory = context.user_data.get('upload_subcategory')
    
    # Save to database without caption
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute(
        "INSERT INTO files (filename, file_id, caption, category, subcategory) VALUES (?, ?, ?, ?, ?)",
        (file_name, file_id, '', category, subcategory)
    )
    conn.commit()
    conn.close()
    
    # Clear user data
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

# ==================== UPLOAD TEXT FUNCTIONS ====================
async def upload_text_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await query.edit_message_text("⛔ Access denied!")
        return ConversationHandler.END
    
    # Clear any existing data
    context.user_data.clear()
    
    await query.edit_message_text(
        "📝 **Upload Text**\n\nSelect category for this text:",
        reply_markup=upload_category_keyboard(),
        parse_mode='Markdown'
    )
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
    
    await query.edit_message_text(
        f"📝 **Upload Text** → {category.upper()}\n\nPlease enter the title for your text:\n\nType /cancel to cancel.",
        parse_mode='Markdown'
    )
    return GET_TEXT_TITLE

async def get_text_title(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await update.message.reply_text("⛔ Access denied!")
        return ConversationHandler.END
    
    context.user_data['text_title'] = update.message.text
    
    await update.message.reply_text(
        "📝 Now please enter the content for your text:\n\nType /cancel to cancel.",
        parse_mode='Markdown'
    )
    return GET_TEXT_CONTENT

async def get_text_content(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await update.message.reply_text("⛔ Access denied!")
        return ConversationHandler.END
    
    title = context.user_data.get('text_title', '')
    content = update.message.text
    category = context.user_data.get('text_category', '')
    
    # Save to database
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute(
        "INSERT INTO texts (title, content, category) VALUES (?, ?, ?)",
        (title, content, category)
    )
    conn.commit()
    conn.close()
    
    # Clear user data
    context.user_data.clear()
    
    await update.message.reply_text(
        f"✅ Text saved successfully!\n\n"
        f"📁 **Category:** {category.upper()}\n"
        f"📌 **Title:** {title}\n"
        f"📄 **Content:** {content[:100]}...",
        reply_markup=admin_panel_keyboard(),
        parse_mode='Markdown'
    )
    return ConversationHandler.END

# ==================== FILE MANAGEMENT FUNCTIONS ====================
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
    message += "• `/deletetext [ID]` - Delete a text"
    
    await query.edit_message_text(
        message,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("⬅️ Back to Admin Panel", callback_data='admin_panel')]
        ])
    )

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
    
    # Create keyboard with file info
    keyboard = []
    for file in files:
        file_id, filename, category, subcategory = file
        keyboard.append([InlineKeyboardButton(
            f"🗑️ {filename[:20]}... ({category}/{subcategory})", 
            callback_data=f'delete_{file_id}'
        )])
    keyboard.append([InlineKeyboardButton("⬅️ Back to Admin Panel", callback_data='admin_panel')])
    
    await query.edit_message_text(
        "🗑️ **Delete File**\n\nSelect a file to delete:",
        reply_markup=InlineKeyboardMarkup(keyboard),
        parse_mode='Markdown'
    )
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
        
        await query.edit_message_text(
            "✅ File deleted successfully!",
            reply_markup=admin_panel_keyboard()
        )
    else:
        await query.edit_message_text("Error deleting file!", reply_markup=admin_panel_keyboard())
    
    return ConversationHandler.END

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        return ConversationHandler.END
    
    await update.message.reply_text(
        "Operation cancelled.",
        reply_markup=admin_panel_keyboard()
    )
    return ConversationHandler.END

# ==================== COMMAND FUNCTIONS ====================
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
            await context.bot.send_document(
                chat_id=update.effective_chat.id,
                document=file_id_db,
                caption=caption or "Here is your file!",
                parse_mode='Markdown'
            )
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
            await update.message.reply_text(
                f"📌 **{title}**\n\n{content}",
                parse_mode='Markdown'
            )
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

# ==================== MAIN BUTTON HANDLER ====================
async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    # Main Menu
    if query.data == 'main_menu':
        await query.edit_message_text(
            "📱 **Main Menu**\n\nPlease select an option:",
            reply_markup=main_menu_keyboard(),
            parse_mode='Markdown'
        )
    
    # DTAC Menu
    elif query.data == 'dtac':
        await query.edit_message_text(
            "📡 **DTAC Packages**\n\nPlease select an option:",
            reply_markup=dtac_menu_keyboard(),
            parse_mode='Markdown'
        )
    elif query.data == 'dtac_zivpn':
        # Send files from DTAC ZIVPN category
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("SELECT file_id, caption FROM files WHERE category='dtac' AND subcategory='dtac_zivpn' ORDER BY uploaded_at DESC")
        files = c.fetchall()
        conn.close()
        
        if files:
            for file_id, caption in files:
                try:
                    await context.bot.send_document(
                        chat_id=update.effective_chat.id,
                        document=file_id,
                        caption=caption or "DTAC ZIVPN File",
                        parse_mode='Markdown'
                    )
                except Exception as e:
                    logger.error(f"Error sending file: {e}")
            
            await query.edit_message_text(
                "🔒 **DTAC ZIVPN Files Sent**\n\nAll available files have been sent.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to DTAC Menu", callback_data='dtac')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
        else:
            await query.edit_message_text(
                "🔒 **DTAC ZIVPN**\n\nNo files available for this category yet.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to DTAC Menu", callback_data='dtac')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
    
    elif query.data == 'dtac_gaming':
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("SELECT file_id, caption FROM files WHERE category='dtac' AND subcategory='dtac_gaming' ORDER BY uploaded_at DESC")
        files = c.fetchall()
        conn.close()
        
        if files:
            for file_id, caption in files:
                try:
                    await context.bot.send_document(
                        chat_id=update.effective_chat.id,
                        document=file_id,
                        caption=caption or "DTAC GAMING File",
                        parse_mode='Markdown'
                    )
                except Exception as e:
                    logger.error(f"Error sending file: {e}")
            
            await query.edit_message_text(
                "🎮 **DTAC GAMING Files Sent**\n\nAll available files have been sent.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to DTAC Menu", callback_data='dtac')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
        else:
            await query.edit_message_text(
                "🎮 **DTAC GAMING**\n\nNo files available for this category yet.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to DTAC Menu", callback_data='dtac')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
    
    elif query.data == 'dtac_nopro':
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("SELECT file_id, caption FROM files WHERE category='dtac' AND subcategory='dtac_nopro' ORDER BY uploaded_at DESC")
        files = c.fetchall()
        conn.close()
        
        if files:
            for file_id, caption in files:
                try:
                    await context.bot.send_document(
                        chat_id=update.effective_chat.id,
                        document=file_id,
                        caption=caption or "DTAC NOPRO File",
                        parse_mode='Markdown'
                    )
                except Exception as e:
                    logger.error(f"Error sending file: {e}")
            
            await query.edit_message_text(
                "🔓 **DTAC NOPRO Files Sent**\n\nAll available files have been sent.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to DTAC Menu", callback_data='dtac')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
        else:
            await query.edit_message_text(
                "🔓 **DTAC NOPRO**\n\nNo files available for this category yet.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to DTAC Menu", callback_data='dtac')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
    
    # TRUE Menu
    elif query.data == 'true':
        await query.edit_message_text(
            "📶 **TRUE Packages**\n\nPlease select an option:",
            reply_markup=true_menu_keyboard(),
            parse_mode='Markdown'
        )
    elif query.data == 'true_twitter':
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("SELECT file_id, caption FROM files WHERE category='true' AND subcategory='true_twitter' ORDER BY uploaded_at DESC")
        files = c.fetchall()
        conn.close()
        
        if files:
            for file_id, caption in files:
                try:
                    await context.bot.send_document(
                        chat_id=update.effective_chat.id,
                        document=file_id,
                        caption=caption or "TRUE TWITTER File",
                        parse_mode='Markdown'
                    )
                except Exception as e:
                    logger.error(f"Error sending file: {e}")
            
            await query.edit_message_text(
                "🐦 **TRUE TWITTER Files Sent**\n\nAll available files have been sent.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to TRUE Menu", callback_data='true')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
        else:
            await query.edit_message_text(
                "🐦 **TRUE TWITTER**\n\nNo files available for this category yet.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to TRUE Menu", callback_data='true')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
    
    elif query.data == 'true_vdo':
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("SELECT file_id, caption FROM files WHERE category='true' AND subcategory='true_vdo' ORDER BY uploaded_at DESC")
        files = c.fetchall()
        conn.close()
        
        if files:
            for file_id, caption in files:
                try:
                    await context.bot.send_document(
                        chat_id=update.effective_chat.id,
                        document=file_id,
                        caption=caption or "TRUE VDO File",
                        parse_mode='Markdown'
                    )
                except Exception as e:
                    logger.error(f"Error sending file: {e}")
            
            await query.edit_message_text(
                "🎬 **TRUE VDO Files Sent**\n\nAll available files have been sent.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to TRUE Menu", callback_data='true')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
        else:
            await query.edit_message_text(
                "🎬 **TRUE VDO**\n\nNo files available for this category yet.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to TRUE Menu", callback_data='true')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
    
    # AIS Menu
    elif query.data == 'ais':
        await query.edit_message_text(
            "🌐 **AIS Packages**\n\nPlease select an option:",
            reply_markup=ais_menu_keyboard(),
            parse_mode='Markdown'
        )
    elif query.data == 'ais_64kbps':
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("SELECT file_id, caption FROM files WHERE category='ais' AND subcategory='ais_64kbps' ORDER BY uploaded_at DESC")
        files = c.fetchall()
        conn.close()
        
        if files:
            for file_id, caption in files:
                try:
                    await context.bot.send_document(
                        chat_id=update.effective_chat.id,
                        document=file_id,
                        caption=caption or "AIS 64 KBPS File",
                        parse_mode='Markdown'
                    )
                except Exception as e:
                    logger.error(f"Error sending file: {e}")
            
            await query.edit_message_text(
                "🌐 **AIS 64 KBPS Files Sent**\n\nAll available files have been sent.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to AIS Menu", callback_data='ais')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
        else:
            await query.edit_message_text(
                "🌐 **AIS 64 KBPS**\n\nNo files available for this category yet.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to AIS Menu", callback_data='ais')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
    
    # ATOM Menu
    elif query.data == 'atom':
        await query.edit_message_text(
            "⚡ **ATOM Packages**\n\nPlease select an option:",
            reply_markup=atom_menu_keyboard(),
            parse_mode='Markdown'
        )
    elif query.data == 'atom_500mb':
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("SELECT file_id, caption FROM files WHERE category='atom' AND subcategory='atom_500mb' ORDER BY uploaded_at DESC")
        files = c.fetchall()
        conn.close()
        
        if files:
            for file_id, caption in files:
                try:
                    await context.bot.send_document(
                        chat_id=update.effective_chat.id,
                        document=file_id,
                        caption=caption or "ATOM 500 MB DAILY File",
                        parse_mode='Markdown'
                    )
                except Exception as e:
                    logger.error(f"Error sending file: {e}")
            
            await query.edit_message_text(
                "📊 **ATOM 500 MB DAILY Files Sent**\n\nAll available files have been sent.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to ATOM Menu", callback_data='atom')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
        else:
            await query.edit_message_text(
                "📊 **ATOM 500 MB DAILY**\n\nNo files available for this category yet.",
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("⬅️ Back to ATOM Menu", callback_data='atom')],
                    [InlineKeyboardButton("🏠 Main Menu", callback_data='main_menu')]
                ])
            )
    
    # DONATE
    elif query.data == 'donate':
        await query.edit_message_text(
            donate_menu(),
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("⬅️ Back to Main Menu", callback_data='main_menu')]
            ])
        )
    
    # ADMIN PANEL
    elif query.data == 'admin_panel':
        await admin_panel_start(update, context)
    
    # ADMIN FUNCTIONS
    elif query.data == 'upload_file':
        await upload_file_start(update, context)
    elif query.data == 'upload_text':
        await upload_text_start(update, context)
    elif query.data == 'delete_file':
        await delete_file_start(update, context)
    elif query.data == 'list_files':
        await list_files_callback(update, context)
    
    # UPLOAD CATEGORY SELECTION
    elif query.data.startswith('upload_category_'):
        await select_upload_category(update, context)
    
    # UPLOAD SUBCATEGORY SELECTION
    elif query.data.startswith('upload_subcategory_'):
        await select_upload_subcategory(update, context)

# ==================== MAIN FUNCTION ====================
def main():
    # Initialize database
    init_database()
    
    # Check token
    if not TOKEN or TOKEN == "your_bot_token_here":
        print("Error: Please set TELEGRAM_BOT_TOKEN in .env file")
        print("Get token from @BotFather on Telegram")
        return
    
    # Create application
    application = Application.builder().token(TOKEN).build()
    
    # Add command handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("menu", menu_command))
    application.add_handler(CommandHandler("sendfile", send_file_command))
    application.add_handler(CommandHandler("sendtext", send_text_command))
    application.add_handler(CommandHandler("listfiles", list_files_command))
    application.add_handler(CommandHandler("deletefile", delete_file_command))
    
    # Add main button handler
    application.add_handler(CallbackQueryHandler(button_handler))
    
    # Admin conversation handler for file upload
    upload_file_conversation = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(upload_file_start, pattern='^upload_file$'),
        ],
        states={
            UPLOAD_CATEGORY: [
                CallbackQueryHandler(select_upload_category, pattern='^upload_category_'),
            ],
            UPLOAD_SUBCATEGORY: [
                CallbackQueryHandler(select_upload_subcategory, pattern='^upload_subcategory_'),
            ],
            UPLOAD_FILE: [
                MessageHandler(
                    filters.Document.ALL | filters.PHOTO | filters.VIDEO | filters.AUDIO,
                    handle_file_upload
                ),
            ],
            UPLOAD_CAPTION: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, handle_file_caption),
                CommandHandler('skip', skip_caption),
            ],
        },
        fallbacks=[
            CommandHandler('cancel', cancel),
            CallbackQueryHandler(admin_panel_start, pattern='^admin_panel$'),
            CallbackQueryHandler(cancel, pattern='^cancel$'),
        ],
    )
    
    # Admin conversation handler for text upload
    upload_text_conversation = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(upload_text_start, pattern='^upload_text$'),
        ],
        states={
            UPLOAD_CATEGORY: [
                CallbackQueryHandler(get_text_category, pattern='^upload_category_'),
            ],
            GET_TEXT_TITLE: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, get_text_title),
            ],
            GET_TEXT_CONTENT: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, get_text_content),
            ],
        },
        fallbacks=[
            CommandHandler('cancel', cancel),
            CallbackQueryHandler(admin_panel_start, pattern='^admin_panel$'),
        ],
    )
    
    # Delete file conversation
    delete_conversation = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(delete_file_start, pattern='^delete_file$'),
            CallbackQueryHandler(confirm_delete, pattern='^delete_'),
        ],
        states={
            DELETE_FILE: [
                CallbackQueryHandler(confirm_delete, pattern='^delete_'),
            ],
            CONFIRM_DELETE: [
                CallbackQueryHandler(execute_delete, pattern='^confirm_delete_yes$'),
                CallbackQueryHandler(admin_panel_start, pattern='^admin_panel$'),
            ],
        },
        fallbacks=[
            CommandHandler('cancel', cancel),
            CallbackQueryHandler(admin_panel_start, pattern='^admin_panel$'),
        ],
    )
    
    application.add_handler(upload_file_conversation)
    application.add_handler(upload_text_conversation)
    application.add_handler(delete_conversation)
    
    # Start the bot
    print("🤖 Bot is starting...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()
EOF
    
    print_color "✓ bot.py created" "$GREEN"
}

# Function to create run scripts
create_run_scripts() {
    print_color "Creating run scripts..." "$BLUE"
    
    # Create run-bot.sh
    cat > run-bot.sh << 'EOF'
#!/bin/bash
cd ~/telegram-bot
source venv/bin/activate
python3 bot.py
EOF
    chmod +x run-bot.sh
    
    # Create start-bot.sh
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
echo "Logs: ~/telegram-bot/bot.log"
echo "Check status: tail -f ~/telegram-bot/bot.log"
EOF
    chmod +x start-bot.sh
    
    # Create stop-bot.sh
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
    
    # Create restart-bot.sh
    cat > restart-bot.sh << 'EOF'
#!/bin/bash
cd ~/telegram-bot
./stop-bot.sh
sleep 2
./start-bot.sh
EOF
    chmod +x restart-bot.sh
    
    # Create update script
    cat > update.sh << 'EOF'
#!/bin/bash
cd ~/telegram-bot
echo "Updating system packages..."
sudo apt update -y
sudo apt upgrade -y
echo "Updating Python packages..."
source venv/bin/activate
pip install --upgrade python-telegram-bot python-dotenv
echo "Bot updated successfully!"
echo "Restarting bot..."
./restart-bot.sh
EOF
    chmod +x update.sh
}

# Function to create systemd service
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

# Function to show final instructions
show_instructions() {
    clear
    print_color "==========================================" "$BLUE"
    print_color "INSTALLATION COMPLETE!" "$GREEN"
    print_color "==========================================" "$BLUE"
    echo ""
    
    print_color "📁 Bot Directory: ~/telegram-bot" "$YELLOW"
    print_color "🔧 Config File: ~/telegram-bot/.env" "$YELLOW"
    print_color "🚀 Main File: ~/telegram-bot/bot.py" "$YELLOW"
    echo ""
    
    print_color "==========================================" "$BLUE"
    print_color "HOW TO SETUP MENU BUTTON" "$BLUE"
    print_color "==========================================" "$BLUE"
    echo ""
    
    print_color "Follow these steps to add menu button to your bot:" "$YELLOW"
    echo "1. Open Telegram and search for @BotFather"
    echo "2. Send /mybots command"
    echo "3. Select your bot"
    echo "4. Choose 'Bot Settings'"
    echo "5. Choose 'Menu Button'"
    echo "6. Choose 'Configure Menu Button'"
    echo "7. Click 'Edit Commands'"
    echo "8. Add these commands (one per line):"
    echo "   start - Start the bot"
    echo "   menu - Show main menu"
    echo "   help - Show help"
    echo "   listfiles - List all files (admin only)"
    echo "9. Click 'Save'"
    echo "10. Now users will see menu button (☰) in your bot!"
    echo ""
    
    print_color "==========================================" "$BLUE"
    print_color "HOW TO RUN YOUR BOT" "$BLUE"
    print_color "==========================================" "$BLUE"
    echo ""
    
    print_color "Option 1: Run manually" "$YELLOW"
    echo "  cd ~/telegram-bot"
    echo "  ./run-bot.sh"
    echo ""
    
    print_color "Option 2: Start/Stop scripts" "$YELLOW"
    echo "  ./start-bot.sh    # Start bot in background"
    echo "  ./stop-bot.sh     # Stop bot"
    echo "  ./restart-bot.sh  # Restart bot"
    echo "  ./update.sh       # Update bot"
    echo ""
    
    print_color "Option 3: Systemd service (auto-start)" "$YELLOW"
    echo "  sudo cp telegram-bot.service /etc/systemd/system/"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl enable telegram-bot.service"
    echo "  sudo systemctl start telegram-bot.service"
    echo "  sudo systemctl status telegram-bot.service"
    echo ""
    
    print_color "Option 4: Tmux session" "$YELLOW"
    echo "  tmux new -s telegram-bot"
    echo "  cd ~/telegram-bot && ./run-bot.sh"
    echo "  Ctrl+B, D to detach"
    echo "  tmux attach -t telegram-bot"
    echo ""
    
    print_color "==========================================" "$BLUE"
    print_color "NEW FEATURES" "$BLUE"
    print_color "==========================================" "$BLUE"
    echo ""
    
    print_color "✅ File Upload with Category Selection" "$GREEN"
    print_color "   - Category (DTAC, TRUE, AIS, ATOM) ရွေး" "$GREEN"
    print_color "   - Subcategory ထပ်ရွေး (DTAC ZIVPN, GAMING, NOPRO)" "$GREEN"
    print_color "   - File ပို့" "$GREEN"
    print_color "   - Caption ထည့်" "$GREEN"
    print_color "✅ Database မှာ category/subcategory သိမ်း" "$GREEN"
    print_color "✅ Users က category ရွေးရင် အဲ့ category အောက်က files တွေအားလုံးပို့" "$GREEN"
    print_color "✅ Menu Button Setup Guide" "$GREEN"
    print_color "✅ New commands: /listfiles, /deletefile" "$GREEN"
    print_color "✅ Back buttons in all menus" "$GREEN"
    echo ""
    
    print_color "==========================================" "$BLUE"
    print_color "HOW TO USE" "$BLUE"
    print_color "==========================================" "$BLUE"
    echo ""
    
    print_color "1. Upload File လုပ်မယ်ဆိုရင်:" "$YELLOW"
    echo "   - Admin Panel → Upload File"
    echo "   - Category ရွေး (DTAC, TRUE, etc.)"
    echo "   - Subcategory ရွေး (DTAC ZIVPN, etc.)"
    echo "   - File ပို့"
    echo "   - Caption ထည့် (or /skip)"
    echo ""
    
    print_color "2. User က File ယူမယ်ဆိုရင်:" "$YELLOW"
    echo "   - Main Menu → DTAC"
    echo "   - DTAC ZIVPN ကိုနှိပ်"
    echo "   - အဲ့ထဲမှာရှိတဲ့ files အားလုံးကို bot က auto ပို့ပေးမယ်"
    echo ""
    
    print_color "3. Menu Navigation:" "$YELLOW"
    echo "   - ဘယ် menu ထဲရောက်နေနေ '⬅️ Back to Main Menu' နှိပ်လိုက်ရင်"
    echo "     main menu ပြန်ရောက်မယ်"
    echo "   - /start ခဏခဏ ခေါ်စရာမလိုဘူး"
    echo ""
    
    print_color "==========================================" "$BLUE"
    print_color "QUICK TEST" "$BLUE"
    print_color "==========================================" "$BLUE"
    echo ""
    
    print_color "1. Open Telegram" "$YELLOW"
    print_color "2. Search for your bot" "$YELLOW"
    print_color "3. Send /start command" "$YELLOW"
    print_color "4. Test all menu buttons" "$YELLOW"
    print_color "5. Try Admin Panel → Upload File" "$YELLOW"
    print_color "6. Menu button (☰) ကိုနှိပ်ပြီး /menu command ကို test လုပ်ပါ" "$YELLOW"
    echo ""
    
    print_color "==========================================" "$BLUE"
    print_color "TROUBLESHOOTING" "$BLUE"
    print_color "==========================================" "$BLUE"
    echo ""
    
    print_color "Check logs: tail -f ~/telegram-bot/bot.log" "$RED"
    print_color "Check token: nano ~/telegram-bot/.env" "$RED"
    print_color "Restart bot: cd ~/telegram-bot && ./restart-bot.sh" "$RED"
    print_color "Update bot: cd ~/telegram-bot && ./update.sh" "$RED"
    echo ""
    
    # Ask to start bot
    read -p "Do you want to start the bot now? (y/n): " start_now
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        cd ~/telegram-bot
        print_color "Starting bot in background..." "$GREEN"
        ./start-bot.sh
        sleep 2
        print_color "Checking bot status..." "$BLUE"
        
        if [ -f "bot.pid" ]; then
            pid=$(cat bot.pid)
            if kill -0 $pid 2>/dev/null; then
                print_color "✓ Bot is running (PID: $pid)" "$GREEN"
                print_color "📋 Logs: tail -f ~/telegram-bot/bot.log" "$YELLOW"
            else
                print_color "✗ Bot failed to start" "$RED"
                print_color "Check logs: cat ~/telegram-bot/bot.log" "$RED"
            fi
        fi
    fi
    
    echo ""
    print_color "Thank you for using JVPN SHOP Bot Installer!" "$GREEN"
    print_color "GitHub: https://github.com/JVPNSHOP/Telegram" "$BLUE"
}

# Main installation flow
main() {
    print_color "Starting installation..." "$GREEN"
    
    # Get user inputs
    get_bot_token
    get_admin_id
    get_additional_admins
    confirm_settings
    
    # Installation steps
    install_dependencies
    setup_project
    create_env_file
    create_bot_file
    create_run_scripts
    create_systemd_service
    
    # Show instructions
    show_instructions
}

# Run main function
main
