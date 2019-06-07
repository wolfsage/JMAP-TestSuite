use jmaptest;

use JMAP::TestSuite::Util qw(calendar);

# Ensure cache (if we hit it) doesn't lose participantId
test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $calendar1 = $account->create_calendar;

  # Create an event
  my $res = $tester->request([[
    "CalendarEvent/set" => {
      create => {
        new => {
          calendarId => $calendar1->id,
          start      => '2019-09-01T05:04:00',
          duration   => "PT1H",
          title      => "Random event",
          participantId => "foo",
          participants => {
            foo => {
              email => $account->credentials->{username},
              kind  => 'individual',
              roles => { attendee => \1, owner => \1, },
            },
            bar => {
              email => 'bar@localhost',
              kind  => 'individual',
              roles => { attendee => \1, },
            },
          },
          replyTo => { imip => 'mailto:example3@localhost' },
        },
      },
    },
  ]]);
  ok($res->is_success, "CalendarEvent/set")
    or diag explain $res->response_payload;

  ok(my $id = $res->sentence(0)->as_set->created_id('new'), 'created an ev')
    or diag explain $res->as_stripped_triples;

  {
    my $get_res = $tester->request([[
      "CalendarEvent/get" => { ids => [ $id ] },
    ]]);
    jcmp_deeply(
      $get_res->sentence(0)->arguments->{list}[0],
      superhashof({
        title         => "Random event",
        participantId => 'foo'
      }),
      "we have a participantId"
    ) or diag explain $get_res->as_stripped_triples;
  }

  # This one should hit cache
  {
    my $get_res = $tester->request([[
      "CalendarEvent/get" => { ids => [ $id ] },
    ]]);
    jcmp_deeply(
      $get_res->sentence(0)->arguments->{list}[0],
      superhashof({
        title         => "Random event",
        participantId => 'foo'
      }),
      "we have a participantId after second request"
    ) or diag explain $get_res->as_stripped_triples;
  }

};
