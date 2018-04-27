use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok pristine_test);

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::More;
use JSON qw(decode_json);
use JSON::Typist;
use Test::Abortable;

test "import then check references" => sub {
  my ($self) = @_;

  my $tester = $self->tester;
  my $context = $self->context;

  my $mailbox = $context->create_mailbox;

  my $blob = $context->email_blob(
    generic => {
      headers => [ 'References' => '<foo>' ],
    },
  );

  my $res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Email/import" => {
        emails => {
          new => {
            blobId => $blob->blobId,
            mailboxIds => { $mailbox->id => JSON::true },
          },
        },
      },
    ]],
  });

  jcmp_deeply(
    $res->single_sentence('Email/import')->arguments,
    {
      accountId  => jstr($self->context->accountId),
      notCreated => {},
      created => {
        new => {
          blobId   => jstr(),
          id       => jstr(),
          size     => jnum(),
          threadId => jstr(),
        },
      },
    },
    'imported',
  ) or diag explain $res->as_stripped_triples;

  my $id = $res->single_sentence('Email/import')->arguments->{created}{new}{id};
  ok($id, 'got the id');

  my $get_res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Email/get" => {
        ids => [ $id ],
        properties => [ qw(references header:references) ],
      },
    ]],
  });

  jcmp_deeply(
    $get_res->single_sentence('Email/get')->arguments->{list}[0],
    superhashof({
      references => [ 'foo' ],
      'header:references' => ' <foo>', # XXX - Why leading space???
    }),
    "got references by header and property"
  ) or diag explain $get_res->as_stripped_triples;
};

run_me;
done_testing;
