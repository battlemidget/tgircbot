#!/usr/bin/env perl
use v5.18;
use strict;
use warnings;

use Data::Printer;

use List::Util qw(max);
use Getopt::Long qw(GetOptions);
use Mojo::JSON qw(decode_json);
use Mojo::IOLoop;
use Mojo::Util;
use Mojo::IRC;
use Mojo::IRC::UA;
use IRC::Utils ();

use WWW::Telegram::BotAPI;
my $CONTEXT = {};

sub message_from_tg_to_irc {
    my $channel = $CONTEXT->{irc_channel} or return;
    my $irc = $CONTEXT->{irc_bot} or return;

    my ($tg_message) = @_;

    if ($tg_message->{text} && $tg_message->{text} ne "") {
        my $text = '<' . $tg_message->{from}{username} . '> ';
        if ($tg_message->{reply_to_message}) {
            $text .= $tg_message->{reply_to_message}{from}{username} . ": ";
        }
        $text .= $tg_message->{text};
        $irc->write(PRIVMSG => $channel, ":$text", sub {});
    } else {
        say "text-less message: " . Mojo::Util::dumper( $tg_message );
    }
}

sub message_from_irc_to_tg {
    my $chat_id = $CONTEXT->{telegram_group_chat_id} or return;
    my $tg = $CONTEXT->{tg_bot} or return;

    my ($irc_message) = @_;

    my $text = $irc_message->{text};
    my $from = $irc_message->{from};
    if ($from =~ /^slackbot/) {
        $from = "";
        if ($text =~ s/\A ( <([a-zA-Z0-9_]+?)> ) \s //x) {
            my $real_nick = $2;
            $text = "<\x{24e2}${real_nick}> $text";
        }
    } else {
        $from = "<$from> ";
    }

    $tg->api_request(
	sendMessage => {
	    chat_id => $chat_id,
	    text    => join('', $from, $text),
	}, sub {
	    my ($ua, $tx) = @_;
	    unless ($tx->success) {
		say "sendMessage failed";
	    }
	});
}

sub tg_get_updates {
    return unless $CONTEXT->{tg_bot} && $CONTEXT->{telegram_group_chat_id};

    state $max_update_id = -1;

    $CONTEXT->{tg_bot}->api_request(
        'getUpdates',
        { offset => $max_update_id + 1 },
        sub {
            my ($ua, $tx) = @_;
            unless ($tx->success) {
                say "getUpdates failed: " . Mojo::Util::dumper( $tx->error );
                return;
            }
            
            my $res = $tx->res->json;
            for (@{$res->{result}}) {
                $max_update_id = max($max_update_id, $_->{update_id});
                if ($CONTEXT->{telegram_group_chat_id} == $_->{message}{chat}{id}) {
                    message_from_tg_to_irc($_->{message});
                } else {
                    say "Unknown chat_id: " . Mojo::Util::dumper($_);
                }
            }
        }
    );
}

sub tg_init {
    my ($token) = @_;
    my $tgbot = WWW::Telegram::BotAPI->new( token => $token, async => 1 );
    $tgbot->api_request(
        'getMe',
        sub {
            my ($ua, $tx) = @_;
            if ($tx->success) {
                my $r = $tx->res->json;
                Mojo::Util::dumper(['getMe', $r]);
            } else {
                die "getMe fail: " . Mojo::Util::dumper($tx->error);
            }
        }
    );
    Mojo::IOLoop->recurring( 15, \&tg_get_updates );
    return $tgbot;
}

sub irc_init {
    my ($nick, $server, $channel) = @_;

    my $irc = Mojo::IRC::UA->new(
        nick => $nick,
        user => $nick,
        server => $server,
    );

    $irc->on(
        error => sub {
            my ($self, $message) = @_;
            p($message);
        });

    $irc->on(
        irc_join => sub {
            my($self, $message) = @_;
            warn "yay! i joined $message->{params}[0]";
        });

    $irc->on(
        irc_privmsg => sub {
            my($self, $message) = @_;
	    my ($c, $text) = @{ $message->{params} };
	    return unless $c eq $channel;

	    my $from_nick = IRC::Utils::parse_user($message->{prefix});
	    message_from_irc_to_tg({ from => $from_nick, text => $text });
        });

    $irc->on(
        irc_rpl_welcome => sub {
            say "-- connected, join $channel";
            $irc->write(join => $channel);
        });

    $irc->on(close => sub {
                 Mojo::IOLoop->timer(
                     5, sub {
                         $irc->connect(sub{ });
                     });
             });

    $irc->register_default_event_handlers;
    $irc->connect(sub {});

    return $irc;   
}

sub MAIN {
    my (%args) = @_;

    $CONTEXT->{irc_server} = $args{irc_server};
    $CONTEXT->{irc_nickname} = $args{irc_nickname};
    $CONTEXT->{irc_channel} = $args{irc_channel};
    $CONTEXT->{telegram_group_chat_id} = $args{telegram_group_chat_id};

    Mojo::IOLoop->timer(
        1, sub {
            $CONTEXT->{irc_bot} = irc_init(
                $args{irc_nickname},
                $args{irc_server},
                $args{irc_channel},
            );
        });

    Mojo::IOLoop->timer(
        3, sub {
            $CONTEXT->{tg_bot} = tg_init( $args{telegram_token} );
        });

    Mojo::IOLoop->start;
}

my %args;
GetOptions(
    \%args,
    "irc_nickname=s",
    "irc_server=s",
    "irc_channel=s",
    "telegram_token=s",
    "telegram_group_chat_id=s",
);
MAIN(%args);
