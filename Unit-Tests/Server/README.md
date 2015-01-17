These are configuration files for the Couchbase Sync Gateway, to serve databases used by the Couchbase Lite unit tests.

Before running the unit tests (specifically, the replicator and ChangeTracker tests), start two instances of Sync Gateway, one with each of the config files.

    term1$ cd Unit-Tests/Server
    term1$ sync_gateway cbl_unit_tests.json

and in another shell:

    term2$ cd Unit-Tests/Server
    term2$ sync_gateway cbl_unit_tests_ssl.json

(You can leave these running indefinitely; they don't need to be restarted every time you run tests.)

## Running the gateways on another host

By default, the tests assume these Gateway instances are running on the same machine (localhost). If they aren't, you'll need to set the environment variable `CBL_TEST_SERVER` to the root URL of the Gateway, e.g. `http://otherhost:4984/`, and set `CBL_SSL_TEST_SERVER` to the root URL of the SSL-enabled Gateway, e.g. `http://otherhost:4994/`. The simplest way to do this is to open the scheme editor, select Test, and configure environment variables in the Arguments tab.
