# Couchbase Lite Unit Test Server

These are configuration files for the Couchbase Sync Gateway, to serve databases that are used by the Couchbase Lite replication unit tests.

## Starting Sync Gateway

Before running the unit tests (specifically, the replicator and ChangeTracker tests), start two instances of Sync Gateway, one with each of the config files.

    term1$ cd Unit-Tests/Server
    term1$ sync_gateway cbl_unit_tests.json

and in another shell:

    term2$ cd Unit-Tests/Server
    term2$ sync_gateway cbl_unit_tests_ssl.json

You can leave these running indefinitely; they don't need to be restarted every time you run tests.

## Testing On A Real iOS (or tvOS) Device

**or, Running The Gateways On Another Host**

By default, the tests assume these Sync Gateway instances are running on the same machine (localhost). That's not going to be the case if you're testing on a real iOS or tvOS device. Or you might just prefer to run the Gateway on another computer for some other reason. In that case, you'll need to (a) tell the unit tests what the root URL of the Sync Gateway is, and (b) create a new SSL certificate that will be valid for that URL.

**(1) Find out the server address.** If the machine running Sync Gateway has an assigned DNS hostname (not a Bonjour `.local` name), use that. Otherwise, look up its IP address from the Network system pref. Remember, this needs to be an address that's reachable by WiFi!

(In the examples below we'll assume the server has an IP address of 66.66.66.66.)

**(2) Verify the address.** First start Sync Gateway as described above. Then open Mobile Safari _on the iOS device_ and enter the Gateway URL, e.g. `http://66.66.66.66:4984/`. Safari should display a JSON response object from SG. (Apple TV doesn't have a web browser, so just do this check on any mobile device on the same WiFi network.)

If Safari fails to connect, first verify that you entered the address and port number correctly. If it still fails, it's possible your WiFi network is blocking peer-to-peer connections for "security" reasons. If that's the case, you'll need to work around it by setting up your own WiFi network (ad-hoc or using a base station) and connecting both the computer and the iOS device to it.

**(3) Tell the unit tests where to connect.** Set the environment variable `CBL_TEST_SERVER` to the root URL of the Gateway, e.g. `http://66.66.66.66:4984/`, and set `CBL_SSL_TEST_SERVER` to the root URL of the SSL-enabled Gateway, e.g. `http://66.66.66.66:4994/`. The simplest way to do this is to open the scheme editor, select Test, and configure environment variables in the Arguments tab.

**(4) Create a new SSL certificate for the Sync Gateway.** The one included in this repo (as `cert.pem` and `SelfSigned.cer`) has a Common Name of `localhost`, which won't match the hostname in the URLs above, causing the client to reject the cert.

The Sync Gateway repo has directions on how to [create a new self-signed SSL cert](https://github.com/couchbase/sync_gateway/wiki/SSL-support#creating-your-own-self-signed-cert). Basically you just need to run these commands:

    cd Unit-Tests/Server   # if you're not there yet
    openssl genrsa -out privkey.pem 2048
    openssl req -new -x509 -sha256 -key privkey.pem -out cert.pem -days 1095

That last command will prompt you for the values of various fields that go in the cert. None of the values matter (you can just press Return to accept the default), _except_ for Common Name (CN) -- when asked for that, enter the Sync Gateway server's hostname/address.

**(5) Tell the unit tests about the new cert.** The unit tests need a copy of the cert, so they can register it as trusted, but annoyingly enough iOS needs it in DER format (`.cer`) not PEM. Update the .cer file like so:

    openssl x509 -inform PEM -in cert.pem -outform DER -out ../../TestData/SelfSigned.cer

Now you should be good to go!
