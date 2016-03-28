
A robot for bridging Telegram and IRC.

This robot forward messages between one IRC channel and one telegram group chat.

To use it, first create a telegram robot and obtain its token, and the telegram group chat id.
Then run with these parameters:

    perl tgircbot.pl --telegram_token ... --telegram_group_chat_id ... --irc_server 'chat.freenode.net:6667' --irc_channel '#example' --irc_nickname tgbot_example

