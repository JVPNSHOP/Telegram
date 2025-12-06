#!/bin/bash

# Telegram Bot Auto Installer with Interactive Setup
# Ubuntu 20.04 to 24.04 Compatible

clear
echo "=========================================="
echo "Telegram Bot Interactive Installer"
echo "Ubuntu 20.04 to 24.04"
echo "=========================================="

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo "Error: Please do not run as root/sudo!"
    echo "Run as normal user: ./installer.sh"
    exit 1
fi

# Function to get user input with validation
get_input() {
    local prompt="$1"
    local var_name="$2"
    local is_required="$3"
    
    while true; do
        read -p "$prompt: " input
        
        if [ -z "$input" ] && [ "$is_required" = "required" ]; then
            echo "This field is required! Please try again."
        elif [ "$var_name" = "ADMIN_ID" ] && ! [[ "$input" =~ ^[0-9]+$ ]]; then
            echo "Admin ID must be a number! Please try again."
        else
            eval "$var_name=\"$input\""
            break
        fi
    done
}

# Function to get bot token from user
get_bot_token() {
    echo ""
    echo "==============================="
    echo "STEP 1: Bot Token Setup"
    echo "==============================="
    echo ""
    echo "To get Bot Token:"
    echo "1. Open Telegram and search for @BotFather"
    echo "2. Send /newbot command"
    echo "3. Follow instructions to create new bot"
    echo "4. Copy the token (looks like: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz)"
    echo ""
    
    while true; do
        read -p "Enter your Bot Token: " BOT_TOKEN
        
        if [ -z "$BOT_TOKEN" ]; then
            echo "Bot Token is required! Please try again."
        elif [[ ! "$BOT_TOKEN" =~ ^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$ ]]; then
            echo "Invalid Bot Token format!"
            echo "Token should look like: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"
            echo "Please try again."
        else
            echo "✓ Bot Token accepted!"
            break
        fi
    done
}

# Function to get admin ID
get_admin_id() {
    echo ""
    echo "==============================="
    echo "STEP 2: Admin ID Setup"
    echo "==============================="
    echo ""
    echo "To get your Telegram User ID:"
    echo "1. Open Telegram and search for @userinfobot"
    echo "2. Send /start command"
    echo "3. Copy your numeric ID (e.g., 123456789)"
    echo ""
    
    while true; do
        read -p "Enter your Admin ID (numbers only): " ADMIN_ID
        
        if [ -z "$ADMIN_ID" ]; then
            echo "Admin ID is required! Please try again."
        elif ! [[ "$ADMIN_ID" =~ ^[0-9]+$ ]]; then
            echo "Admin ID must contain only numbers! Please try again."
        else
            echo "✓ Admin ID accepted!"
            break
        fi
    done
}

# Function to get additional admin IDs
get_additional_admins() {
    echo ""
    echo "Do you want to add additional admin users? (y/n)"
    read -p "Choice: " add_more
    
    ADDITIONAL_ADMINS=""
    if [[ "$add_more" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Enter additional Admin IDs (one per line)."
        echo "Press Enter on empty line to finish."
        
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
                ((count++))
                echo "✓ Added Admin ID: $admin_id"
            else
                echo "Invalid ID. Please enter numbers only."
            fi
        done
    fi
}

# Function to confirm settings
confirm_settings() {
    clear
    echo "=========================================="
    echo "SETTINGS CONFIRMATION"
    echo "=========================================="
    echo ""
    echo "Bot Token: ${BOT_TOKEN:0:15}..."
    echo "Main Admin ID: $ADMIN_ID"
    
    if [ -n "$ADDITIONAL_ADMINS" ]; then
        echo "Additional Admins: $ADDITIONAL_ADMINS"
        ALL_ADMINS="$ADMIN_ID,$ADDITIONAL_ADMINS"
    else
        ALL_ADMINS="$ADMIN_ID"
    fi
    
    echo ""
    echo "Database will be stored in: ~/telegram-bot/data/"
    echo "Files will be stored in: ~/telegram-bot/data/files/"
    echo ""
    
    read -p "Are these settings correct? (y/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 0
    fi
}

# Main installation function
install_bot() {
    echo ""
    echo "=========================================="
    echo "STARTING INSTALLATION"
    echo "=========================================="
    
    # Update system
    echo "Updating system packages..."
    sudo apt update -y > /dev/null 2>&1
    sudo apt upgrade -y > /dev/null 2>&1
    
    # Install required system packages
    echo "Installing system dependencies..."
    sudo apt install -y python3 python3-pip python3-venv git sqlite3 > /dev/null 2>&1
    
    # Create project directory
    echo "Creating project directory..."
    cd ~
    rm -rf telegram-bot 2>/dev/null
    mkdir -p telegram-bot
    cd telegram-bot
    
    # Create virtual environment
    echo "Setting up Python virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    
    # Install Python packages
    echo "Installing Python packages..."
    pip install python-telegram-bot==20.7 python-dotenv==1.0.0 > /dev/null 2>&1
    
    # Create directory structure
    echo "Creating directory structure..."
    mkdir -p data/files
    
    # Create .env file with user's credentials
    echo "Creating configuration file..."
    cat > .env << EOF
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
ADMIN_IDS=$ALL_ADMINS
EOF
    
    # Create main bot file
    echo "Creating main bot file..."
    cat > bot.py << 'EOF'
import os
import logging
import sqlite3
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler, 
    MessageHandler, filters, ContextTypes, ConversationHandler
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
            uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS texts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            content TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()

# ==================== KEYBOARD FUNCTIONS ====================
def main_menu_keyboard():
    keyboard = [
        [InlineKeyboardButton("DTAC", callback_data='dtac')],
        [InlineKeyboardButton("TRUE", callback_data='true')],
        [InlineKeyboardButton("AIS", callback_data='ais')],
        [InlineKeyboardButton("ATOM", callback_data='atom')],
        [InlineKeyboardButton("DONATE", callback_data='donate')],
        [InlineKeyboardButton("ADMIN PANEL", callback_data='admin_panel')]
    ]
    return InlineKeyboardMarkup(keyboard)

def dtac_menu_keyboard():
    keyboard = [
        [InlineKeyboardButton("DTAC ZIVPN", callback_data='dtac_zivpn')],
        [InlineKeyboardButton("DTAC GAMING", callback_data='dtac_gaming')],
        [InlineKeyboardButton("Back to Main Menu", callback_data='main_menu')]
    ]
    return InlineKeyboardMarkup(keyboard)

def true_menu_keyboard():
    keyboard = [
        [InlineKeyboardButton("TRUE TWITTER", callback_data='true_twitter')],
        [InlineKeyboardButton("TRUE VDO", callback_data='true_vdo')],
        [InlineKeyboardButton("Back to Main Menu", callback_data='main_menu')]
    ]
    return InlineKeyboardMarkup(keyboard)

def ais_menu_keyboard():
    keyboard = [
        [InlineKeyboardButton("AIS 64 KBPS", callback_data='ais_64kbps')],
        [InlineKeyboardButton("Back to Main Menu", callback_data='main_menu')]
    ]
    return InlineKeyboardMarkup(keyboard)

def atom_menu_keyboard():
    keyboard = [
        [InlineKeyboardButton("ATOM 500 MB DAILY", callback_data='atom_500mb')],
        [InlineKeyboardButton("Back to Main Menu", callback_data='main_menu')]
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

📱 **Contact Admin:** @your_admin_username
"""
    await update.message.reply_text(help_text, parse_mode='Markdown')

async def menu_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "Main Menu:",
        reply_markup=main_menu_keyboard()
    )

# ==================== ADMIN STATES ====================
UPLOAD_FILE, UPLOAD_TEXT, DELETE_FILE, CONFIRM_DELETE = range(4)

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
        return
    
    await query.edit_message_text(
        "🔧 **Admin Panel**\n\nSelect an option:",
        reply_markup=admin_panel_keyboard(),
        parse_mode='Markdown'
    )
    return ConversationHandler.END

async def upload_file_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    await query.edit_message_text(
        "📤 **Upload File**\n\nPlease send me the file you want to upload.\n\nType /cancel to cancel.",
        parse_mode='Markdown'
    )
    return UPLOAD_FILE

async def handle_file_upload(update: Update, context: ContextTypes.DEFAULT_TYPE):
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
    
    # Save file info to database
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute(
        "INSERT INTO files (filename, file_id, caption) VALUES (?, ?, ?)",
        (file.file_name or f"{file_type}_{file.file_id}", file.file_id, update.message.caption or "")
    )
    conn.commit()
    conn.close()
    
    await update.message.reply_text(
        f"✅ File uploaded successfully!\nFilename: {file.file_name or 'N/A'}\nType: {file_type}",
        reply_markup=admin_panel_keyboard()
    )
    return ConversationHandler.END

async def upload_text_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    await query.edit_message_text(
        "📝 **Upload Text**\n\nPlease send the text in this format:\n\nTitle: Your Title Here\nContent: Your text content here...\n\nType /cancel to cancel.",
        parse_mode='Markdown'
    )
    return UPLOAD_TEXT

async def handle_text_upload(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text
    lines = text.split('\n')
    title = ""
    content = ""
    
    for line in lines:
        if line.lower().startswith('title:'):
            title = line[6:].strip()
        elif line.lower().startswith('content:'):
            content = line[8:].strip()
    
    if not title or not content:
        await update.message.reply_text("Please use format: Title: ...\nContent: ...")
        return UPLOAD_TEXT
    
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute("INSERT INTO texts (title, content) VALUES (?, ?)", (title, content))
    conn.commit()
    conn.close()
    
    await update.message.reply_text(
        f"✅ Text saved!\nTitle: {title}\nContent: {content[:50]}...",
        reply_markup=admin_panel_keyboard()
    )
    return ConversationHandler.END

async def list_files_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute("SELECT id, filename FROM files ORDER BY uploaded_at DESC LIMIT 10")
    files = c.fetchall()
    c.execute("SELECT id, title FROM texts ORDER BY created_at DESC LIMIT 10")
    texts = c.fetchall()
    conn.close()
    
    message = "📋 **Stored Files & Texts**\n\n"
    
    if files:
        message += "📁 **Files:**\n"
        for file_id, filename in files:
            message += f"• {filename} (ID: {file_id})\n"
    else:
        message += "📁 No files uploaded yet.\n"
    
    message += "\n📝 **Texts:**\n"
    if texts:
        for text_id, title in texts:
            message += f"• {title} (ID: {text_id})\n"
    else:
        message += "No texts uploaded yet.\n"
    
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
    
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute("SELECT id, filename FROM files ORDER BY uploaded_at DESC")
    files = c.fetchall()
    conn.close()
    
    if not files:
        await query.edit_message_text("No files to delete!", reply_markup=admin_panel_keyboard())
        return ConversationHandler.END
    
    keyboard = []
    for file_id, filename in files:
        keyboard.append([InlineKeyboardButton(f"🗑️ {filename}", callback_data=f'delete_{file_id}')])
    keyboard.append([InlineKeyboardButton("Cancel", callback_data='admin_panel')])
    
    await query.edit_message_text(
        "🗑️ **Delete File**\n\nSelect a file to delete:",
        reply_markup=InlineKeyboardMarkup(keyboard),
        parse_mode='Markdown'
    )
    return DELETE_FILE

async def confirm_delete(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    file_id = int(query.data.split('_')[1])
    context.user_data['delete_file_id'] = file_id
    
    conn = sqlite3.connect('data/database.db')
    c = conn.cursor()
    c.execute("SELECT filename FROM files WHERE id = ?", (file_id,))
    result = c.fetchone()
    conn.close()
    
    if result:
        await query.edit_message_text(
            f"⚠️ Delete: {result[0]}?\n\nThis cannot be undone!",
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
    
    file_id = context.user_data.get('delete_file_id')
    
    if file_id:
        conn = sqlite3.connect('data/database.db')
        c = conn.cursor()
        c.execute("DELETE FROM files WHERE id = ?", (file_id,))
        conn.commit()
        conn.close()
        
        await query.edit_message_text("✅ File deleted!", reply_markup=admin_panel_keyboard())
    else:
        await query.edit_message_text("Error!", reply_markup=admin_panel_keyboard())
    
    return ConversationHandler.END

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("Cancelled.", reply_markup=admin_panel_keyboard())
    return ConversationHandler.END

async def send_file_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.args:
        await update.message.reply_text("Usage: /sendfile [file_id]")
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
                caption=caption or "Here is your file!"
            )
        else:
            await update.message.reply_text("File not found!")
    except:
        await update.message.reply_text("Error!")

# ==================== MAIN BUTTON HANDLER ====================
async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    # Main Menu
    if query.data == 'main_menu':
        await query.edit_message_text("Main Menu:", reply_markup=main_menu_keyboard())
    
    # DTAC Menu
    elif query.data == 'dtac':
        await query.edit_message_text("📡 DTAC Packages:", reply_markup=dtac_menu_keyboard())
    elif query.data == 'dtac_zivpn':
        await query.edit_message_text("🔒 **DTAC ZIVPN**\n\nZIVPN for DTAC\nPrice: 1500 MMK/month", parse_mode='Markdown')
    elif query.data == 'dtac_gaming':
        await query.edit_message_text("🎮 **DTAC GAMING**\n\nGaming package\nPrice: 2000 MMK/month", parse_mode='Markdown')
    
    # TRUE Menu
    elif query.data == 'true':
        await query.edit_message_text("📶 TRUE Packages:", reply_markup=true_menu_keyboard())
    elif query.data == 'true_twitter':
        await query.edit_message_text("🐦 **TRUE TWITTER**\n\nTwitter package\nPrice: 1000 MMK/month", parse_mode='Markdown')
    elif query.data == 'true_vdo':
        await query.edit_message_text("🎬 **TRUE VDO**\n\nVideo package\nPrice: 2500 MMK/month", parse_mode='Markdown')
    
    # AIS Menu
    elif query.data == 'ais':
        await query.edit_message_text("📶 AIS Packages:", reply_markup=ais_menu_keyboard())
    elif query.data == 'ais_64kbps':
        await query.edit_message_text("🌐 **AIS 64 KBPS**\n\n64 Kbps unlimited\nPrice: 300 MMK/month", parse_mode='Markdown')
    
    # ATOM Menu
    elif query.data == 'atom':
        await query.edit_message_text("⚛️ ATOM Packages:", reply_markup=atom_menu_keyboard())
    elif query.data == 'atom_500mb':
        await query.edit_message_text("📊 **ATOM 500 MB DAILY**\n\n500MB daily\nPrice: 5000 MMK/month", parse_mode='Markdown')
    
    # DONATE
    elif query.data == 'donate':
        await query.edit_message_text(
            donate_menu(),
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("Back to Main Menu", callback_data='main_menu')]
            ])
        )
    
    # ADMIN PANEL
    elif query.data == 'admin_panel':
        await admin_panel_start(update, context)
    
    # ADMIN FUNCTIONS
    elif query.data == 'list_files':
        await list_files_callback(update, context)

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
    
    # Add main button handler
    application.add_handler(CallbackQueryHandler(button_handler))
    
    # Admin conversation handler
    admin_conversation = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(upload_file_start, pattern='^upload_file$'),
            CallbackQueryHandler(upload_text_start, pattern='^upload_text$'),
            CallbackQueryHandler(delete_file_start, pattern='^delete_file$'),
            CallbackQueryHandler(confirm_delete, pattern='^delete_'),
            CallbackQueryHandler(execute_delete, pattern='^confirm_delete_yes$'),
        ],
        states={
            UPLOAD_FILE: [MessageHandler(filters.ALL & ~filters.COMMAND, handle_file_upload)],
            UPLOAD_TEXT: [MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text_upload)],
            DELETE_FILE: [CallbackQueryHandler(confirm_delete, pattern='^delete_')],
            CONFIRM_DELETE: [
                CallbackQueryHandler(execute_delete, pattern='^confirm_delete_yes$'),
                CallbackQueryHandler(admin_panel_start, pattern='^admin_panel$')
            ],
        },
        fallbacks=[
            CommandHandler('cancel', cancel),
            CallbackQueryHandler(admin_panel_start, pattern='^admin_panel$')
        ],
    )
    
    application.add_handler(admin_conversation)
    
    # Start the bot
    print("🤖 Bot is starting...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()
EOF

    # Create run script
    cat > run-bot.sh << 'EOF'
#!/bin/bash
cd ~/telegram-bot
source venv/bin/activate
python3 bot.py
EOF

    chmod +x run-bot.sh
    
    # Create systemd service file
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

    # Create update script
    cat > update-bot.sh << 'EOF'
#!/bin/bash
cd ~/telegram-bot
echo "Updating system packages..."
sudo apt update -y
sudo apt upgrade -y
echo "Updating Python packages..."
source venv/bin/activate
pip install --upgrade python-telegram-bot python-dotenv
echo "Bot updated successfully!"
EOF

    chmod +x update-bot.sh
    
    echo "✓ Installation completed!"
}

# Function to show installation summary
show_summary() {
    clear
    echo "=========================================="
    echo "INSTALLATION COMPLETE!"
    echo "=========================================="
    echo ""
    echo "📁 Bot Directory: ~/telegram-bot"
    echo "🔧 Config File: ~/telegram-bot/.env"
    echo "🚀 Run Script: ~/telegram-bot/run-bot.sh"
    echo ""
    echo "=========================================="
    echo "HOW TO RUN YOUR BOT"
    echo "=========================================="
    echo ""
    echo "OPTION 1: Run manually (for testing)"
    echo "  cd ~/telegram-bot"
    echo "  ./run-bot.sh"
    echo ""
    echo "OPTION 2: Run as system service (auto-start)"
    echo "  cd ~/telegram-bot"
    echo "  sudo cp telegram-bot.service /etc/systemd/system/"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl enable telegram-bot.service"
    echo "  sudo systemctl start telegram-bot.service"
    echo "  sudo systemctl status telegram-bot.service"
    echo ""
    echo "OPTION 3: Check bot logs"
    echo "  sudo journalctl -u telegram-bot.service -f"
    echo ""
    echo "=========================================="
    echo "BOT FEATURES"
    echo "=========================================="
    echo "✅ DTAC, TRUE, AIS, ATOM, DONATE menus"
    echo "✅ Admin panel for file management"
    echo "✅ File upload/download/delete"
    echo "✅ SQLite database"
    echo "✅ Ubuntu 20.04-24.04 compatible"
    echo ""
    echo "=========================================="
    echo "QUICK TEST"
    echo "=========================================="
    echo "1. Open Telegram and search for your bot"
    echo "2. Send /start command"
    echo "3. Test all menu buttons"
    echo "4. Use Admin Panel (only for your Admin ID)"
    echo ""
    
    read -p "Do you want to start the bot now? (y/n): " start_now
    
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        echo "Starting bot in background..."
        cd ~/telegram-bot
        tmux new-session -d -s telegram-bot './run-bot.sh'
        echo "Bot started in tmux session: telegram-bot"
        echo "To attach: tmux attach -t telegram-bot"
        echo "To detach: Ctrl+B then D"
    fi
}

# Main execution flow
main() {
    get_bot_token
    get_admin_id
    get_additional_admins
    confirm_settings
    install_bot
    show_summary
}

# Run main function
main
