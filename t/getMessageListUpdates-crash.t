use strict;
use warnings;

use JMAP::TestSuite;
use Test::Deep::JType 0.004;
use JMAP::TestSuite::Util qw(batch_ok);
use Test::More;
use Email::MessageID;

my $server = JMAP::TestSuite->get_server;

$server->simple_test(sub {
  my ($context) = @_;

  my $tester = $context->tester;

  my $batch = $context->create_batch(mailbox => {
    x => { name => "Folder X at $^T.$$", parentId => undef },
  });

  batch_ok($batch);

  ok( $batch->is_entirely_successful, "created a mailbox");
  my $x = $batch->result_for('x');

  my $msg_id = Email::MessageID->new->in_brackets;
  my $blob = $context->email_blob(generic => { message_id => $msg_id });
  ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

  $batch = $context->import_messages({
    msg => { blobId => $blob, mailboxIds => [ $x->id ] },
  });

  my $res = $tester->request([
    [
      getMessageList => {
        filter => { inMailbox => $x->id },
      },
    ],
  ]);

  my $state = $res->single_sentence->arguments->{state};
  ok($state, 'got state');

  my $res = $context->tester->request([
    [
      # These work
      # getMessageListUpdates => { filter => { inMailbox => $x->id }, sinceState => $state  },
      # getMessageListUpdates => { sinceState => "1"  },
      # getMessageListUpdates => { sinceState => "0" },

      # These die (because numeric type, not string?)
      # getMessageListUpdates => { sinceState => jnum(0) },
      getMessageListUpdates => { sinceState => jnum(1) },
    ]
  ]);

  ok($res->is_success, 'called getMessageUpdates')
    or diag explain $res->http_response->as_string;
});

done_testing;
