# NAME

WWW::Sentry

# VERSION

version 0.01

# SYNOPSIS

    my $sentry = Reg::Sentry->new( $dsn, tags => { type => 'autocharge' } );

    $sentry->fatal( 'msg' );
    $sentry->error( 'msg' );
    $sentry->warn ( 'msg' );
    $sentry->warning ( 'msg' );  # alias to warn
    $sentry->info ( 'msg' );
    $sentry->debug( 'msg' );

    $sentry->error( $error_msg, extra => { var1 => $var1 } );

All this methods is getting event id as result or die with error

#### new

Constructor

    my $sentry = Reg::Sentry->new(
        'http://public_key:secret_key@example.com/project-id',
        sentry_version    => 5 # can be omitted
    );

See also

https://docs.sentry.io/clientdev/overview/#parsing-the-dsn

#### send

Send a message to Sentry server.
Returns the id of inserted message or dies.

%params:
    message\*  -- error message
    event\_id  -- message id (by default it's random)
    level     -- 'fatal', 'error', 'warning', 'info', 'debug' ('error' by default)
    logger    -- the name of the logger which created the record, e.g 'sentry.errors'
    platform  -- A string representing the platform the SDK is submitting from. E.g. 'python'
    culprit   -- The name of the transaction (or culprit) which caused this exception. For example, in a web app, this might be the route name: /welcome/
    tags      -- tags for this event (could be array or hash )
    server\_name -- host from which the event was recorded
    modules   -- a list of relevant modules and their versions
    environment -- environment name, such as ‘production’ or ‘staging’.
    extra     -- hash ref of additional data. Non scalar values are Dumperized forcely.

\* - required params

All other interfaces could be also provided as %params, e.g.

    stacktrace -- array ref  or string
    user       -- hash ref user info

See also

https://docs.sentry.io/clientdev/overview/#building-the-json-packet
https://docs.sentry.io/clientdev/attributes/
https://docs.sentry.io/clientdev/interfaces/

# NAME

Module for sending messages to Sentry that implements Sentry reporting API

# AUTHOR

Pavel Serikov <pavelsr@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2018 by Pavel Serikov.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
