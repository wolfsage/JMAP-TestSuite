package JMAP::TestSuite::JMAP::Tester::WithSugarRole;
use strict;
use warnings;

use Params::Util qw(_ARRAY0 _HASH);

use Moo::Role;
use Test::More;
use Test::Deep::JType;
use Try::Tiny;

use feature qw(state);

sub BUILD {
  my $self = shift;

  unless ($self->_has_default_using) {
    $self->default_using(
      [ "urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail", "urn:ietf:params:jmap:submission"],
    );
  }
}

sub request_ok {
  my ($self, $input_request, $expect_paragraphs, $desc) = @_;

  # Allow ->request_ok([ foo => { ... } ], superhashof({...}), ...)
  if (
         _ARRAY0($input_request)
    && ! _ARRAY0($input_request->[0])
    && ! _ARRAY0($expect_paragraphs)
  ) {
    $input_request = [ $input_request ];
    $expect_paragraphs = [[ $expect_paragraphs ]];
  }

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my ($res, $failures);

  subtest "$desc" => sub {
    state $ident = 'a';
    my %seen;
    my @suffixed;
    my @req_client_ids;
    my @req_sentence_names;

    my $request = _ARRAY0($input_request)
                ? { methodCalls => $input_request }
                : { %$input_request };

    for my $call (@{ $request->{methodCalls} }) {
      my $cid;

      my $copy = [ @$call ];
      if (defined $copy->[2]) {
        $seen{$call->[2]}++;

        $cid = $call->[2];
      } else {
        my $next;
        do { $next = $ident++ } until ! $seen{$ident}++;
        $cid = $copy->[2] = $next;
      }

      push @suffixed, $copy;
      push @req_client_ids, $cid;

      push @req_sentence_names, $call->[0];
    }

    $request->{methodCalls} = \@suffixed;

    $res = $self->request($request);

    # Check success, give diagnostic on failure
    ok($res->is_success, 'JMAP request succeeded')
      or die "Request failed: " . $res->response_payload;

    for my $expect_para (@$expect_paragraphs) {
      my $cid = shift @req_client_ids;
      my $name = shift @req_sentence_names;

      my $res_para = $res->paragraph_by_client_id($cid);
      unless ($res_para) {
        die   "No paragraph for cid '$cid' in response to '$name'?: "
            . diag explain $res->as_stripped_triples;
      }

      while (@$expect_para) {
        # Allow:
        #
        #   [ superhashof({...}) ]
        #   [ name => superhashof({...}) ]
        #
        # In the first form, we will pick the name based off of the
        # matching request
        my ($expect_name, $expect_struct) = do {
          my $name_or_struct = shift @$expect_para;

          if (ref $name_or_struct) {
            ($name, $name_or_struct);
          } else {
            ($name_or_struct, shift @$expect_para);
          }
       };

        # Will croak if not found
        my $res_sentence = try {
          $res_para->sentence_named($expect_name);
        } catch {
          my $err = $_;
          my ($fl) = $err =~ /\A(.*)$/m;
          note "$fl\n";
          diag explain $res_para->as_stripped_triples;
          die $err;
        };

        ok($res_sentence, "Found a sentence named $expect_name");

        jcmp_deeply(
          $res_sentence->arguments,
          $expect_struct,
          "Sentence for cid '$cid' in response to '$name' matches up"
        ) or $failures++;
      }
    }

    if ($failures) {
      diag explain $res->as_stripped_triples;
    }
  };

  # So you can my ($res) = ->request_ok(...)
  if (wantarray) {
    return $res;
  };

  # So you can ->request_ok(..) or foo();
  return ! $failures;
}

1;
