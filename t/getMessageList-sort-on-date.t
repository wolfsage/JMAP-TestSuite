use strict;
use warnings;

use JMAP::TestSuite;
use JMAP::TestSuite::Util qw(batch_ok);

use Test::Deep::JType;
use Test::More;

use DateTime;
use Email::MessageID;

my $server = JMAP::TestSuite->get_server;

$server->simple_test(sub {
  my ($context) = @_;

  my $tester = $context->tester;

  # Get us a mailbox to play with
  my $batch = $context->create_batch(mailbox => {
      x => { name => "Folder X at $^T.$$" },
  });

  batch_ok($batch);

  ok( $batch->is_entirely_successful, "created a mailbox");
  my $x = $batch->result_for('x');

  # Import messages with specific dates, expect
  # the highest to come back when sorting by date desc
  for my $tests (
    [ "Sun, 25 Dec 2010 12:00:01 −0300", '2010-12-25T12:00:01Z', ],
    [ "Sun, 25 Dec 2015 12:00:01 −0300", '2015-12-25T12:00:01Z', ],
    [ "Sun, 25 Dec 2008 12:00:01 −0300", '2015-12-25T12:00:01Z', ],

    # This sorts internally by import date but returns 1970?!
    [ "Junk",                            DateTime->now->ymd()    ],
  ) {
    my ($header_date, $expect_string) = @$tests;

    my $blob = $context->email_blob(generic => {
      message_id => Email::MessageID->new->in_brackets,
      date       => $header_date,
    });

    ok($blob->is_success, "our upload succeeded (" . $blob->blobId . ")");

    $batch = $context->import_messages({
      msg => { blobId => $blob, mailboxIds => [ $x->id ] },
    });

    batch_ok($batch);

    ok($batch->is_entirely_successful, "we uploaded and imported messages");

    my $res = $tester->request([
      [
        getMessageList => {
          filter => { inMailbox   => $x->id },
          sort                    => [ 'date desc' ],
          limit                   => 1,
          fetchMessages           => \1,
          fetchMessageProperties  => [ 'date', ] ,
        }
      ],
    ]);

    my $got_date = $res->sentence(1)->arguments->{list}[0]{date};

    like(
      $got_date,
      qr/\Q$expect_string\E/,
      "After import of $header_date, we got $expect_string as latest"
    );
  }

});

done_testing;
