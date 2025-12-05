#!/usr/bin/env python3
"""
Telegram Server Information Bot
Simplified version with only TrueMoney donation
"""

import os
import json
import logging
import sqlite3
from datetime import datetime
from typing import Dict, List, Optional

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

# ==================== CONFIGURATION ====================
BOT_TOKEN = "YOUR_BOT_TOKEN_HERE"  # 🔴 REPLACE WITH YOUR BOT TOKEN
ADMIN_IDS = [123456789]  # 🔴 REPLACE WITH YOUR TELEGRAM ID

# Database configuration
DB_NAME = "servers.db"

# Conversation states
ADD_SERVER_IP, ADD_SERVER_USERNAME, ADD_SERVER_PASSWORD, ADD_SERVER_EXPIRE, ADD_SERVER_CONFIRM = range(5)

# ==================== SETUP LOGGING ====================
def setup_logging():
    """Setup logging configuration"""
    os.makedirs("logs", exist_ok=True)
    
    logging.basicConfig(
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        level=logging.INFO,
        handlers=[
            logging.FileHandler(f"logs/bot_{datetime.now().strftime('%Y%m%d')}.log"),
            logging.StreamHandler()
        ]
    )
    return logging.getLogger(__name__)

logger = setup_logging()

# ==================== DATABASE ====================
class Database:
    def __init__(self):
        self.init_db()
    
    def init_db(self):
        """Initialize database"""
        conn = sqlite3.connect(DB_NAME)
        cursor = conn.cursor()
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS servers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                provider TEXT NOT NULL,
                plan TEXT NOT NULL,
                server_ip TEXT NOT NULL,
                username TEXT NOT NULL,
                password TEXT NOT NULL,
                expired_date TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                is_active INTEGER DEFAULT 1
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS statistics (
                server_id INTEGER,
                copy_count INTEGER DEFAULT 0,
                FOREIGN KEY (server_id) REFERENCES servers (id)
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def add_server(self, provider: str, plan: str, server_ip: str, 
                  username: str, password: str, expired_date: str) -> int:
        """Add new server to database"""
        conn = sqlite3.connect(DB_NAME)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO servers (provider, plan, server_ip, username, password, expired_date)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (provider, plan, server_ip, username, password, expired_date))
        
        server_id = cursor.lastrowid
        
        cursor.execute('''
            INSERT INTO statistics (server_id) VALUES (?)
        ''', (server_id,))
        
        conn.commit()
        conn.close()
        return server_id
    
    def get_servers(self, provider: str = None, plan: str = None) -> List[Dict]:
        """Get servers with optional filters"""
        conn = sqlite3.connect(DB_NAME)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        query = '''
            SELECT s.*, st.copy_count 
            FROM servers s
            LEFT JOIN statistics st ON s.id = st.server_id
            WHERE s.is_active = 1
        '''
        params = []
        
        if provider:
            query += " AND s.provider = ?"
            params.append(provider)
        
        if plan:
            query += " AND s.plan = ?"
            params.append(plan)
        
        query += " ORDER BY s.created_at DESC"
        
        cursor.execute(query, params)
        rows = cursor.fetchall()
        
        servers = [dict(row) for row in rows]
        conn.close()
        return servers
    
    def get_server(self, server_id: int) -> Optional[Dict]:
        """Get single server by ID"""
        conn = sqlite3.connect(DB_NAME)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT s.*, st.copy_count 
            FROM servers s
            LEFT JOIN statistics st ON s.id = st.server_id
            WHERE s.id = ? AND s.is_active = 1
        ''', (server_id,))
        
        row = cursor.fetchone()
        conn.close()
        return dict(row) if row else None
    
    def delete_server(self, server_id: int) -> bool:
        """Delete server"""
        conn = sqlite3.connect(DB_NAME)
        cursor = conn.cursor()
        
        cursor.execute('UPDATE servers SET is_active = 0 WHERE id = ?', (server_id,))
        affected = cursor.rowcount
        conn.commit()
        conn.close()
        return affected > 0
    
    def increment_copy_count(self, server_id: int):
        """Increment copy count for a server"""
        conn = sqlite3.connect(DB_NAME)
        cursor = conn.cursor()
        
        cursor.execute('''
            UPDATE statistics SET copy_count = copy_count + 1 WHERE server_id = ?
        ''', (server_id,))
        
        conn.commit()
        conn.close()

# Initialize database
db = Database()

# ==================== KEYBOARD BUILDERS ====================
class Keyboards:
    """Keyboard templates"""
    
    @staticmethod
    def main_menu(user_id: int):
        """Main menu keyboard"""
        keyboard = [
            [InlineKeyboardButton("📱 DTAC", callback_data="provider_dtac")],
            [InlineKeyboardButton("🔵 TRUE", callback_data="provider_true")],
            [InlineKeyboardButton("📶 AIS", callback_data="provider_ais")],
            [InlineKeyboardButton("💰 Donate", callback_data="donate")],
            [InlineKeyboardButton("ℹ️ Help", callback_data="help")]
        ]
        
        if user_id in ADMIN_IDS:
            keyboard.append([InlineKeyboardButton("👑 Admin", callback_data="admin_panel")])
        
        return InlineKeyboardMarkup(keyboard)
    
    @staticmethod
    def provider_menu(provider: str):
        """Provider plans menu"""
        plans = {
            "dtac": [
                "DTAC GAME PLAN",
                "DTAC ZIVPN (အရံနက်)",
                "DTAC NOPRO"
            ],
            "true": [
                "TRUE TWITTER PLAN", 
                "TRUE VIBER PLAN"
            ],
            "ais": [
                "V2RAY 64KBPS"
            ]
        }
        
        keyboard = []
        for plan in plans.get(provider, []):
            keyboard.append([InlineKeyboardButton(plan, callback_data=f"plan_{provider}_{plan}")])
        
        keyboard.append([InlineKeyboardButton("🔙 Main Menu", callback_data="main_menu")])
        return InlineKeyboardMarkup(keyboard)
    
    @staticmethod
    def server_menu(server_id: int, provider: str, plan: str):
        """Server info with copy buttons"""
        keyboard = [
            [InlineKeyboardButton("🌐 Copy IP", callback_data=f"copy_ip_{server_id}")],
            [InlineKeyboardButton("👤 Copy Username", callback_data=f"copy_user_{server_id}")],
            [InlineKeyboardButton("🔑 Copy Password", callback_data=f"copy_pass_{server_id}")],
            [InlineKeyboardButton("📅 Copy Expiry", callback_data=f"copy_expire_{server_id}")],
            [
                InlineKeyboardButton("📋 More Servers", callback_data=f"plan_{provider}_{plan}"),
                InlineKeyboardButton("🏠 Main Menu", callback_data="main_menu")
            ]
        ]
        return InlineKeyboardMarkup(keyboard)
    
    @staticmethod
    def donate_menu():
        """Donation menu (TrueMoney only)"""
        keyboard = [
            [InlineKeyboardButton("📱 TrueMoney Wallet", callback_data="donate_truemoney")],
            [InlineKeyboardButton("🔙 Main Menu", callback_data="main_menu")]
        ]
        return InlineKeyboardMarkup(keyboard)
    
    @staticmethod
    def admin_menu():
        """Admin panel menu"""
        keyboard = [
            [InlineKeyboardButton("➕ Add Server", callback_data="admin_add")],
            [InlineKeyboardButton("🗑️ Delete Server", callback_data="admin_delete")],
            [InlineKeyboardButton("📋 Server List", callback_data="admin_list")],
            [InlineKeyboardButton("🔙 Main Menu", callback_data="main_menu")]
        ]
        return InlineKeyboardMarkup(keyboard)
    
    @staticmethod
    def admin_add_menu():
        """Admin add server - provider selection"""
        keyboard = [
            [InlineKeyboardButton("📱 DTAC", callback_data="add_dtac")],
            [InlineKeyboardButton("🔵 TRUE", callback_data="add_true")],
            [InlineKeyboardButton("📶 AIS", callback_data="add_ais")],
            [InlineKeyboardButton("🔙 Admin Panel", callback_data="admin_panel")]
        ]
        return InlineKeyboardMarkup(keyboard)
    
    @staticmethod
    def admin_plan_menu(provider: str):
        """Admin add server - plan selection"""
        plans = {
            "dtac": ["DTAC GAME PLAN", "DTAC ZIVPN (အရံနက်)", "DTAC NOPRO"],
            "true": ["TRUE TWITTER PLAN", "TRUE VIBER PLAN"],
            "ais": ["V2RAY 64KBPS"]
        }
        
        keyboard = []
        for plan in plans.get(provider, []):
            keyboard.append([InlineKeyboardButton(plan, callback_data=f"addplan_{provider}_{plan}")])
        
        keyboard.append([InlineKeyboardButton("🔙 Back", callback_data="admin_add")])
        return InlineKeyboardMarkup(keyboard)
    
    @staticmethod
    def delete_confirmation(server_id: int):
        """Delete confirmation"""
        keyboard = [
            [
                InlineKeyboardButton("✅ Yes, Delete", callback_data=f"delete_yes_{server_id}"),
                InlineKeyboardButton("❌ Cancel", callback_data="admin_panel")
            ]
        ]
        return InlineKeyboardMarkup(keyboard)

# ==================== MESSAGE FORMATTERS ====================
class Messages:
    """Message templates"""
    
    @staticmethod
    def server_info(server: Dict) -> str:
        """Format server information"""
        return f"""
🌐 **Server Information**

📱 **Provider:** {server['provider'].upper()}
📋 **Plan:** {server['plan']}

📡 **Server IP:** `{server['server_ip']}`
👤 **Username:** `{server['username']}`
🔑 **Password:** `{server['password']}`
📅 **Expired Date:** `{server['expired_date']}`

📊 **Copied:** {server.get('copy_count', 0)} times
        """
    
    @staticmethod
    def donate_info() -> str:
        """Donation information"""
        return """
💰 **Support Our Service**

**💳 TrueMoney Wallet:**
`0953244179`

ဆာဗာများထပ်တိုးချင်ရင် Donate ပေးနိုင်ပါတယ်ဗျ။

**ငွေလွှဲပြီးပါက Screenshot ဖြင့် Admin ကို ပေးပို့ပါ။**

ကျေးဇူးတင်ပါတယ်။ 🙏
        """

# ==================== BOT HANDLERS ====================
class BotHandlers:
    """Bot command handlers"""
    
    def __init__(self):
        self.user_data = {}
    
    async def start(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        
        welcome = f"""
🤖 **Welcome {user.first_name}!**

Select your internet provider to get server information.
Each server comes with easy copy buttons for quick setup.
        """
        
        await update.message.reply_text(
            welcome,
            reply_markup=Keyboards.main_menu(user.id),
            parse_mode="Markdown"
        )
    
    async def help(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        help_text = """
❓ **How to Use**

1. Select Provider (DTAC/TRUE/AIS)
2. Select Plan
3. View server information
4. Use copy buttons to copy details

**📋 Copy Buttons:**
• 🌐 Server IP
• 👤 Username  
• 🔑 Password
• 📅 Expiry Date

**💰 Donate:**
Help us add more servers by donating via TrueMoney.

Need help? Contact admin.
        """
        
        await update.message.reply_text(help_text, parse_mode="Markdown")
    
    async def button_handler(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle all button presses"""
        query = update.callback_query
        await query.answer()
        
        user = query.from_user
        data = query.data
        
        # Main menu
        if data == "main_menu":
            await self.show_main_menu(query)
        
        # Provider selection
        elif data.startswith("provider_"):
            provider = data.replace("provider_", "")
            await query.edit_message_text(
                f"📡 **{provider.upper()} Plans**\n\nSelect a plan:",
                reply_markup=Keyboards.provider_menu(provider),
                parse_mode="Markdown"
            )
        
        # Plan selection
        elif data.startswith("plan_"):
            parts = data.split("_")
            provider = parts[1]
            plan = "_".join(parts[2:])
            await self.show_servers(query, provider, plan)
        
        # Copy buttons
        elif data.startswith("copy_"):
            parts = data.split("_")
            action = parts[1]  # ip, user, pass, expire
            server_id = int(parts[2])
            await self.handle_copy(query, server_id, action)
        
        # Donation
        elif data == "donate":
            await query.edit_message_text(
                Messages.donate_info(),
                reply_markup=Keyboards.donate_menu(),
                parse_mode="Markdown"
            )
        elif data == "donate_truemoney":
            await query.edit_message_text(
                Messages.donate_info(),
                reply_markup=Keyboards.donate_menu(),
                parse_mode="Markdown"
            )
        
        # Admin panel
        elif data == "admin_panel":
            if user.id in ADMIN_IDS:
                await query.edit_message_text(
                    "👑 **Admin Panel**\n\nSelect an action:",
                    reply_markup=Keyboards.admin_menu(),
                    parse_mode="Markdown"
                )
            else:
                await query.answer("❌ Admin only!", show_alert=True)
        
        # Admin add server
        elif data == "admin_add":
            if user.id in ADMIN_IDS:
                await query.edit_message_text(
                    "➕ **Add Server**\n\nSelect provider:",
                    reply_markup=Keyboards.admin_add_menu(),
                    parse_mode="Markdown"
                )
            else:
                await query.answer("❌ Admin only!", show_alert=True)
        
        elif data.startswith("add_"):
            if user.id in ADMIN_IDS:
                provider = data.replace("add_", "")
                self.user_data[user.id] = {"provider": provider}
                
                await query.edit_message_text(
                    f"📱 **Provider:** {provider.upper()}\n\nSelect plan:",
                    reply_markup=Keyboards.admin_plan_menu(provider),
                    parse_mode="Markdown"
                )
            else:
                await query.answer("❌ Admin only!", show_alert=True)
        
        elif data.startswith("addplan_"):
            if user.id in ADMIN_IDS:
                parts = data.split("_")
                provider = parts[1]
                plan = "_".join(parts[2:])
                
                self.user_data[user.id] = {"provider": provider, "plan": plan}
                
                await query.edit_message_text(
                    f"📋 **Plan:** {plan}\n\n"
                    "📡 **Enter Server IP:**\n\n"
                    "Example: `192.168.1.1` or `vpn.server.com`",
                    parse_mode="Markdown"
                )
                return ADD_SERVER_IP
            else:
                await query.answer("❌ Admin only!", show_alert=True)
                return ConversationHandler.END
        
        # Admin delete server
        elif data == "admin_delete":
            if user.id in ADMIN_IDS:
                servers = db.get_servers()
                if servers:
                    message = "🗑️ **Delete Server**\n\n"
                    keyboard = []
                    
                    for server in servers[:10]:  # Show first 10
                        btn_text = f"❌ {server['server_ip']} ({server['plan']})"
                        keyboard.append([
                            InlineKeyboardButton(btn_text, callback_data=f"delete_{server['id']}")
                        ])
                    
                    keyboard.append([InlineKeyboardButton("🔙 Admin Panel", callback_data="admin_panel")])
                    
                    await query.edit_message_text(
                        message,
                        reply_markup=InlineKeyboardMarkup(keyboard),
                        parse_mode="Markdown"
                    )
                else:
                    await query.edit_message_text(
                        "📭 No servers to delete.",
                        reply_markup=Keyboards.admin_menu()
                    )
            else:
                await query.answer("❌ Admin only!", show_alert=True)
        
        elif data.startswith("delete_"):
            if user.id in ADMIN_IDS:
                if data.startswith("delete_yes_"):
                    server_id = int(data.replace("delete_yes_", ""))
                    if db.delete_server(server_id):
                        await query.edit_message_text(
                            "✅ Server deleted successfully!",
                            reply_markup=Keyboards.admin_menu()
                        )
                    else:
                        await query.edit_message_text(
                            "❌ Failed to delete server.",
                            reply_markup=Keyboards.admin_menu()
                        )
                else:
                    server_id = int(data.replace("delete_", ""))
                    server = db.get_server(server_id)
                    
                    if server:
                        await query.edit_message_text(
                            f"⚠️ **Confirm Delete**\n\n"
                            f"Plan: {server['plan']}\n"
                            f"IP: {server['server_ip']}\n"
                            f"Username: {server['username']}\n\n"
                            f"Are you sure?",
                            reply_markup=Keyboards.delete_confirmation(server_id),
                            parse_mode="Markdown"
                        )
            else:
                await query.answer("❌ Admin only!", show_alert=True)
        
        # Admin list servers
        elif data == "admin_list":
            if user.id in ADMIN_IDS:
                servers = db.get_servers()
                
                if servers:
                    message = "📋 **All Servers**\n\n"
                    for server in servers:
                        message += f"• {server['plan']}\n"
                        message += f"  IP: `{server['server_ip']}`\n"
                        message += f"  User: `{server['username']}`\n"
                        message += f"  Expires: {server['expired_date']}\n"
                        message += f"  Copies: {server.get('copy_count', 0)}\n\n"
                    
                    await query.edit_message_text(
                        message[:4000],
                        reply_markup=Keyboards.admin_menu(),
                        parse_mode="Markdown"
                    )
                else:
                    await query.edit_message_text(
                        "📭 No servers found.",
                        reply_markup=Keyboards.admin_menu()
                    )
            else:
                await query.answer("❌ Admin only!", show_alert=True)
    
    async def show_main_menu(self, query):
        """Show main menu"""
        user = query.from_user
        await query.edit_message_text(
            "🤖 **Select Provider:**",
            reply_markup=Keyboards.main_menu(user.id),
            parse_mode="Markdown"
        )
    
    async def show_servers(self, query, provider: str, plan: str):
        """Show servers for a plan"""
        servers = db.get_servers(provider=provider, plan=plan)
        
        if not servers:
            await query.edit_message_text(
                f"📭 **No servers available for {plan}**\n\n"
                "Please check back later or try another plan.",
                reply_markup=Keyboards.provider_menu(provider)
            )
            return
        
        # Show first server
        server = servers[0]
        await query.edit_message_text(
            Messages.server_info(server),
            reply_markup=Keyboards.server_menu(server['id'], provider, plan),
            parse_mode="Markdown"
        )
    
    async def handle_copy(self, query, server_id: int, action: str):
        """Handle copy button press"""
        server = db.get_server(server_id)
        
        if not server:
            await query.answer("❌ Server not found!", show_alert=True)
            return
        
        # Get text to copy
        if action == "ip":
            text = server['server_ip']
            field = "Server IP"
        elif action == "user":
            text = server['username']
            field = "Username"
        elif action == "pass":
            text = server['password']
            field = "Password"
        elif action == "expire":
            text = server['expired_date']
            field = "Expiry Date"
        else:
            return
        
        # Increment copy count
        db.increment_copy_count(server_id)
        
        # Show success message
        await query.answer(f"✅ {field} copied: {text}")
        
        # Refresh message with updated count
        server = db.get_server(server_id)
        provider = server['provider']
        plan = server['plan']
        
        await query.edit_message_text(
            Messages.server_info(server),
            reply_markup=Keyboards.server_menu(server_id, provider, plan),
            parse_mode="Markdown"
        )
    
    # ========== CONVERSATION HANDLERS ==========
    async def add_server_ip(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Receive server IP"""
        user = update.effective_user
        
        if user.id not in ADMIN_IDS:
            await update.message.reply_text("❌ Admin only!")
            return ConversationHandler.END
        
        server_ip = update.message.text.strip()
        
        if user.id not in self.user_data:
            self.user_data[user.id] = {}
        
        self.user_data[user.id]["server_ip"] = server_ip
        
        await update.message.reply_text(
            f"🌐 **Server IP:** `{server_ip}`\n\n"
            "👤 **Enter Username:**\n\n"
            "Example: `user123`",
            parse_mode="Markdown"
        )
        return ADD_SERVER_USERNAME
    
    async def add_server_username(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Receive username"""
        user = update.effective_user
        
        if user.id not in ADMIN_IDS:
            await update.message.reply_text("❌ Admin only!")
            return ConversationHandler.END
        
        username = update.message.text.strip()
        self.user_data[user.id]["username"] = username
        
        await update.message.reply_text(
            f"👤 **Username:** `{username}`\n\n"
            "🔑 **Enter Password:**\n\n"
            "Example: `password123`",
            parse_mode="Markdown"
        )
        return ADD_SERVER_PASSWORD
    
    async def add_server_password(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Receive password"""
        user = update.effective_user
        
        if user.id not in ADMIN_IDS:
            await update.message.reply_text("❌ Admin only!")
            return ConversationHandler.END
        
        password = update.message.text.strip()
        self.user_data[user.id]["password"] = password
        
        await update.message.reply_text(
            f"🔑 **Password:** `{password}`\n\n"
            "📅 **Enter Expiry Date:**\n\n"
            "Format: `YYYY-MM-DD` or `DD/MM/YYYY`\n"
            "Example: `2024-12-31`",
            parse_mode="Markdown"
        )
        return ADD_SERVER_EXPIRE
    
    async def add_server_expire(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Receive expiry date"""
        user = update.effective_user
        
        if user.id not in ADMIN_IDS:
            await update.message.reply_text("❌ Admin only!")
            return ConversationHandler.END
        
        expired_date = update.message.text.strip()
        self.user_data[user.id]["expired_date"] = expired_date
        
        # Show confirmation
        data = self.user_data[user.id]
        
        confirm_text = f"""
✅ **Confirm Server Details**

📱 **Provider:** {data['provider'].upper()}
📋 **Plan:** {data['plan']}
🌐 **Server IP:** `{data['server_ip']}`
👤 **Username:** `{data['username']}`
🔑 **Password:** `{data['password']}`
📅 **Expiry Date:** `{data['expired_date']}`

**Add this server?**
        """
        
        keyboard = InlineKeyboardMarkup([
            [
                InlineKeyboardButton("✅ Yes, Add", callback_data="confirm_add"),
                InlineKeyboardButton("❌ Cancel", callback_data="admin_panel")
            ]
        ])
        
        await update.message.reply_text(
            confirm_text,
            reply_markup=keyboard,
            parse_mode="Markdown"
        )
        return ADD_SERVER_CONFIRM
    
    async def confirm_add_server(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Confirm and add server"""
        query = update.callback_query
        await query.answer()
        
        user = query.from_user
        
        if user.id not in ADMIN_IDS or user.id not in self.user_data:
            await query.edit_message_text("❌ Session expired.")
            return ConversationHandler.END
        
        data = self.user_data[user.id]
        
        try:
            # Add to database
            server_id = db.add_server(
                provider=data['provider'],
                plan=data['plan'],
                server_ip=data['server_ip'],
                username=data['username'],
                password=data['password'],
                expired_date=data['expired_date']
            )
            
            await query.edit_message_text(
                f"🎉 **Server Added Successfully!**\n\n"
                f"🆔 Server ID: #{server_id}\n"
                f"📡 IP: {data['server_ip']}\n"
                f"👤 Username: {data['username']}\n\n"
                f"Users can now access this server.",
                reply_markup=Keyboards.admin_menu(),
                parse_mode="Markdown"
            )
            
            # Clear user data
            if user.id in self.user_data:
                del self.user_data[user.id]
            
        except Exception as e:
            logger.error(f"Error adding server: {e}")
            await query.edit_message_text(
                f"❌ Error: {str(e)}",
                reply_markup=Keyboards.admin_menu()
            )
        
        return ConversationHandler.END
    
    async def cancel(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Cancel any operation"""
        user = update.effective_user
        
        if user.id in self.user_data:
            del self.user_data[user.id]
        
        await update.message.reply_text(
            "❌ Operation cancelled.",
            reply_markup=Keyboards.main_menu(user.id)
        )
        return ConversationHandler.END

# ==================== MAIN APPLICATION ====================
def main():
    """Main function"""
    # Check token
    if BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
        print("\n" + "="*60)
        print("❌ ERROR: Please update BOT_TOKEN in the script!")
        print("1. Open bot.py with nano or vim")
        print("2. Find line: BOT_TOKEN = \"YOUR_BOT_TOKEN_HERE\"")
        print("3. Replace with your bot token from @BotFather")
        print("4. Also update ADMIN_IDS with your Telegram ID")
        print("="*60 + "\n")
        return
    
    # Create application
    app = Application.builder().token(BOT_TOKEN).build()
    handlers = BotHandlers()
    
    # Add command handlers
    app.add_handler(CommandHandler("start", handlers.start))
    app.add_handler(CommandHandler("help", handlers.help))
    app.add_handler(CommandHandler("cancel", handlers.cancel))
    
    # Add callback query handler
    app.add_handler(CallbackQueryHandler(handlers.button_handler, pattern="^(?!confirm_add|delete_yes_).*"))
    
    # Add conversation handler for adding servers
    conv_handler = ConversationHandler(
        entry_points=[CallbackQueryHandler(
            handlers.button_handler, 
            pattern="^addplan_"
        )],
        states={
            ADD_SERVER_IP: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, handlers.add_server_ip)
            ],
            ADD_SERVER_USERNAME: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, handlers.add_server_username)
            ],
            ADD_SERVER_PASSWORD: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, handlers.add_server_password)
            ],
            ADD_SERVER_EXPIRE: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, handlers.add_server_expire)
            ],
            ADD_SERVER_CONFIRM: [
                CallbackQueryHandler(handlers.confirm_add_server, pattern="^confirm_add$"),
                CallbackQueryHandler(handlers.cancel, pattern="^admin_panel$")
            ]
        },
        fallbacks=[CommandHandler("cancel", handlers.cancel)]
    )
    app.add_handler(conv_handler)
    
    # Add confirm delete handler separately
    app.add_handler(CallbackQueryHandler(handlers.button_handler, pattern="^confirm_add$|^delete_yes_"))
    
    # Error handler
    async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
        logger.error(f"Error: {context.error}")
        if update:
            logger.error(f"Update: {update}")
    
    app.add_error_handler(error_handler)
    
    # Start bot
    print("\n" + "="*60)
    print("🤖 Server Information Bot Starting...")
    print(f"👑 Admin IDs: {ADMIN_IDS}")
    print("💾 Database: servers.db")
    print("📁 Logs: logs/ directory")
    print("="*60 + "\n")
    
    app.run_polling(allowed_updates=Update.ALL_UPDATES)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n👋 Bot stopped by user")
    except Exception as e:
        print(f"\n❌ Error: {e}")
        logger.error(f"Bot crashed: {e}")
