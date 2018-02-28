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

test "Mailbox/changes with no changes" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $before = $self->context->get_state('mailbox');

  warn "BEFORE STATE: $before\n";

  my $mailbox = $self->context->create_mailbox({
    name => "A new mailbox",
  });

  my $state = $self->context->get_state('mailbox');

  warn "AFTER STATE: $state\n";

  my $res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/changes" => { sinceState => $state, },
    ]],
  });
  ok($res->is_success, "Mailbox/changes")
    or diag explain $res->http_response->as_string;

  jcmp_deeply(
    $res->single_sentence("Mailbox/changes")->arguments,
    superhashof({
      accountId      => jstr($self->context->accountId),
      oldState       => jstr($state),
      newState       => jstr($state),
      hasMoreChanges => jfalse,
      changed        => undef,
      destroyed      => undef,
    }),
    "Response looks good",
  );
};

pristine_test "Mailbox/changes with changes" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  subtest "created entities show up in changed" => sub {
    my $state = $self->context->get_state('mailbox');

    my $mailbox = $self->context->create_mailbox({
      name => "A new mailbox",
    });

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => { sinceState => $state, },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        changed        => [ $mailbox->id ],
        destroyed      => undef,
      }),
      "Response looks good",
    );
  };

  subtest "updated entities show up in changed" => sub {
    my $mailbox = $self->context->create_mailbox({
      name => "A new mailbox",
    });

    my $state = $self->context->get_state('mailbox');

    subtest "update the mailbox" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/set" => {
            update => {
              $mailbox->id => { name => "An updated mailbox" },
            },
          },
        ]],
      });
      ok($res->is_success, "Mailbox/set")
        or diag explain $res->http_response->as_string;
    };

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => { sinceState => $state, },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        changed        => [ $mailbox->id ],
        destroyed      => undef,
      }),
      "Response looks good",
    );
  };

  subtest "destroyed entities show up in destroyed" => sub {
    my $mailbox = $self->context->create_mailbox({
      name => "A new mailbox",
    });

    my $state = $self->context->get_state('mailbox');

    subtest "destroy the mailbox" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/set" => {
            destroy => [ $mailbox->id ],
          },
        ]],
      });
      ok($res->is_success, "Mailbox/set")
        or diag explain $res->http_response->as_string;
    };

    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => { sinceState => $state, },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state),
        newState       => none(jstr($state)),
        hasMoreChanges => jfalse,
        changed        => undef,
        destroyed      => [ $mailbox->id ],
      }),
      "Response looks good",
    );
  };
};

test "maxChanges and hasMoreChanges" => sub {
  my ($self) = @_;

  # XXX - Skip if the server under test doesn't support it

  my $tester = $self->tester;

  # Create two mailboxes so we should have 3 states (start state,
  # new mailbox 1 state, new mailbox 2 state). Then, ask for changes
  # from start state, with a maxChanges set to 1 so we should get
  # hasMoreChanges when sinceState is start state.

  my $state1 = $self->context->get_state('mailbox');

  my $mailbox1 = $self->context->create_mailbox({
    name => "A new mailbox",
  });

  my $state2 = $self->context->get_state('mailbox');
  $state2--; # xxx 

  my $mailbox2 = $self->context->create_mailbox({
    name => "A second new mailbox",
  });

  my $state3 = $self->context->get_state('mailbox');

  subtest "changes from start state" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => {
          sinceState => $state1,
          maxChanges => 1,
        },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state1),
#        newState       => jstr($state2), # XXX
        newState       => jstr($state2),
        hasMoreChanges => jtrue,
        changed        => [ $mailbox1->id ],
        destroyed      => undef,
      }),
      "Response looks good",
    ) or diag explain $res->as_stripped_triples;
  };

  subtest "changes from second state to final state" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => {
          sinceState => $state2,
          maxChanges => 1,
        },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    diag explain $res->as_stripped_triples;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state2),
        newState       => jstr($state3),
        hasMoreChanges => jfalse,
        changed        => [ $mailbox2->id ],
        destroyed      => undef,
      }),
      "Response looks good",
    );
  };

  subtest "final state says no changes" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/changes" => {
          sinceState => $state3,
          maxChanges => 1,
        },
      ]],
    });
    ok($res->is_success, "Mailbox/changes")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/changes")->arguments,
      superhashof({
        accountId      => jstr($self->context->accountId),
        oldState       => jstr($state3),
        newState       => jstr($state3),
        hasMoreChanges => jfalse,
        changed        => undef,
        destroyed      => undef,
      }),
      "Response looks good",
    );
  };
};

run_me;
done_testing;
