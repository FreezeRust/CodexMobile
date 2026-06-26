import Foundation

/// Project scaffolds: ready-made folder/file structures generated from a request.
struct Scaffold: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    /// Phrases that trigger auto-detection.
    let keywords: [String]
    /// Folders to create.
    let folders: [String]
    /// Files: path -> content.
    let files: [(path: String, content: String)]
}

enum Scaffolder {
    static let all: [Scaffold] = [discordBot, telegramBot, minecraftMod, webApp]

    /// Detects which scaffold a free-text request asks for, if any.
    static func detect(in text: String) -> Scaffold? {
        let t = text.lowercased()
        for s in all where s.keywords.contains(where: { t.contains($0) }) {
            return s
        }
        return nil
    }

    // MARK: - Discord bot (discord.js)

    static let discordBot = Scaffold(
        id: "discord",
        title: "Discord бот",
        subtitle: "discord.js · команды, события",
        icon: "gamecontroller.fill",
        keywords: ["discord бот", "дискорд бот", "бот discord", "бот дискорд", "discord bot"],
        folders: ["src", "src/commands", "src/events"],
        files: [
            ("package.json", """
            {
              "name": "discord-bot",
              "version": "1.0.0",
              "main": "src/index.js",
              "scripts": { "start": "node src/index.js" },
              "dependencies": { "discord.js": "^14.0.0", "dotenv": "^16.0.0" }
            }
            """),
            (".env", "DISCORD_TOKEN=сюда_вставь_токен\nCLIENT_ID=айди_приложения\n"),
            ("src/index.js", """
            // file: src/index.js
            const { Client, GatewayIntentBits, Collection } = require('discord.js');
            const fs = require('fs');
            const path = require('path');
            require('dotenv').config();

            const client = new Client({
              intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, GatewayIntentBits.MessageContent]
            });

            client.commands = new Collection();
            const cmdDir = path.join(__dirname, 'commands');
            for (const file of fs.readdirSync(cmdDir).filter(f => f.endsWith('.js'))) {
              const cmd = require(path.join(cmdDir, file));
              client.commands.set(cmd.data.name, cmd);
            }

            client.once('ready', () => console.log(`Вошёл как ${client.user.tag}`));

            client.on('interactionCreate', async (interaction) => {
              if (!interaction.isChatInputCommand()) return;
              const cmd = client.commands.get(interaction.commandName);
              if (cmd) await cmd.execute(interaction);
            });

            client.login(process.env.DISCORD_TOKEN);
            """),
            ("src/commands/ping.js", """
            // file: src/commands/ping.js
            const { SlashCommandBuilder } = require('discord.js');
            module.exports = {
              data: new SlashCommandBuilder().setName('ping').setDescription('Проверка отклика'),
              async execute(interaction) {
                await interaction.reply(`Понг! ${interaction.client.ws.ping}мс`);
              }
            };
            """),
            ("src/events/ready.js", """
            // file: src/events/ready.js
            module.exports = {
              name: 'ready',
              once: true,
              execute(client) { console.log('Бот готов:', client.user.tag); }
            };
            """),
            ("README.md", """
            # Discord бот

            ## Запуск
            1. Создай приложение на https://discord.com/developers/applications
            2. Вставь токен в `.env`
            3. `npm install` → `npm start`

            Команды лежат в `src/commands/`, события в `src/events/`.
            """)
        ]
    )

    // MARK: - Telegram bot (node-telegram-bot-api)

    static let telegramBot = Scaffold(
        id: "telegram",
        title: "Telegram бот",
        subtitle: "node-telegram-bot-api · команды",
        icon: "paperplane.fill",
        keywords: ["телеграм бот", "телеграмм бот", "telegram бот", "тг бот", "telegram bot", "бот телеграм"],
        folders: ["src", "src/handlers"],
        files: [
            ("package.json", """
            {
              "name": "telegram-bot",
              "version": "1.0.0",
              "main": "src/index.js",
              "scripts": { "start": "node src/index.js" },
              "dependencies": { "node-telegram-bot-api": "^0.64.0", "dotenv": "^16.0.0" }
            }
            """),
            (".env", "BOT_TOKEN=токен_от_BotFather\n"),
            ("src/index.js", """
            // file: src/index.js
            const TelegramBot = require('node-telegram-bot-api');
            require('dotenv').config();

            const bot = new TelegramBot(process.env.BOT_TOKEN, { polling: true });
            const start = require('./handlers/start');
            const help = require('./handlers/help');

            bot.onText(/\\/start/, (msg) => start(bot, msg));
            bot.onText(/\\/help/, (msg) => help(bot, msg));

            bot.on('message', (msg) => {
              if (msg.text && !msg.text.startsWith('/')) {
                bot.sendMessage(msg.chat.id, `Ты написал: ${msg.text}`);
              }
            });

            console.log('Telegram бот запущен');
            """),
            ("src/handlers/start.js", """
            // file: src/handlers/start.js
            module.exports = (bot, msg) => {
              bot.sendMessage(msg.chat.id, 'Привет! Я бот OpenVolt. Напиши /help для списка команд.');
            };
            """),
            ("src/handlers/help.js", """
            // file: src/handlers/help.js
            module.exports = (bot, msg) => {
              bot.sendMessage(msg.chat.id, 'Команды:\\n/start — начать\\n/help — помощь');
            };
            """),
            ("README.md", """
            # Telegram бот

            ## Запуск
            1. Получи токен у @BotFather
            2. Вставь его в `.env` (BOT_TOKEN)
            3. `npm install` → `npm start`

            Обработчики команд — в `src/handlers/`.
            """)
        ]
    )

    // MARK: - Minecraft mod (Fabric, Java)

    static let minecraftMod = Scaffold(
        id: "minecraft",
        title: "Minecraft мод",
        subtitle: "Fabric · Java 17",
        icon: "cube.fill",
        keywords: ["мод майнкрафт", "майнкрафт мод", "minecraft мод", "мод minecraft", "minecraft mod", "майнкрафт"],
        folders: ["src/main/java/com/example/mod", "src/main/resources"],
        files: [
            ("src/main/java/com/example/mod/ExampleMod.java", """
            // file: src/main/java/com/example/mod/ExampleMod.java
            package com.example.mod;

            import net.fabricmc.api.ModInitializer;
            import org.slf4j.Logger;
            import org.slf4j.LoggerFactory;

            public class ExampleMod implements ModInitializer {
                public static final String MOD_ID = "examplemod";
                public static final Logger LOGGER = LoggerFactory.getLogger(MOD_ID);

                @Override
                public void onInitialize() {
                    LOGGER.info("ExampleMod загружен!");
                }
            }
            """),
            ("src/main/resources/fabric.mod.json", """
            {
              "schemaVersion": 1,
              "id": "examplemod",
              "version": "1.0.0",
              "name": "Example Mod",
              "description": "Мой первый мод на Fabric",
              "authors": ["Ты"],
              "environment": "*",
              "entrypoints": { "main": ["com.example.mod.ExampleMod"] },
              "depends": { "fabricloader": ">=0.15.0", "minecraft": "~1.20.4" }
            }
            """),
            ("build.gradle", """
            plugins { id 'fabric-loom' version '1.5-SNAPSHOT' }
            archivesBaseName = 'example-mod'
            version = '1.0.0'
            group = 'com.example'

            repositories { mavenCentral() }

            dependencies {
                minecraft "com.mojang:minecraft:1.20.4"
                mappings "net.fabricmc:yarn:1.20.4+build.3:v2"
                modImplementation "net.fabricmc:fabric-loader:0.15.6"
            }
            """),
            ("README.md", """
            # Minecraft мод (Fabric)

            ## Сборка
            1. Установи JDK 17
            2. `./gradlew build`
            3. Jar появится в `build/libs/`

            Основной класс: `src/main/java/com/example/mod/ExampleMod.java`.
            Метаданные: `src/main/resources/fabric.mod.json`.
            """)
        ]
    )

    // MARK: - Web app (vanilla)

    static let webApp = Scaffold(
        id: "web",
        title: "Веб-приложение",
        subtitle: "HTML · CSS · JS",
        icon: "globe",
        keywords: ["веб приложение", "веб-приложение", "сайт", "web app", "веб сайт", "лендинг"],
        folders: ["css", "js"],
        files: [
            ("index.html", """
            // file: index.html
            <!DOCTYPE html>
            <html lang="ru">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Моё приложение</title>
              <link rel="stylesheet" href="css/style.css">
            </head>
            <body>
              <h1>Привет, мир!</h1>
              <button id="btn">Нажми меня</button>
              <script src="js/app.js"></script>
            </body>
            </html>
            """),
            ("css/style.css", """
            // file: css/style.css
            body { font-family: -apple-system, sans-serif; display: grid; place-items: center;
                   min-height: 100vh; margin: 0; background: #0d0a1f; color: #fff; }
            button { padding: 12px 24px; border: none; border-radius: 12px;
                     background: #6b55f4; color: #fff; font-size: 16px; cursor: pointer; }
            """),
            ("js/app.js", """
            // file: js/app.js
            document.getElementById('btn').addEventListener('click', () => {
              alert('Работает!');
            });
            """),
            ("README.md", "# Веб-приложение\\n\\nОткрой index.html в браузере или через предпросмотр HTML.")
        ]
    )
}
