We hate bugs, but we love bug reports! And we're grateful to our developers who exercise Couchbase Lite and the Couchbase Sync Gateway in new and unexpected ways and help us work out the kinks.

We also want to hear about your ideas for new features and improvements. You can file those in the issue trackers too.

And while we welcome questions, **we prefer to answer questions on our [mailing list](https://groups.google.com/forum/?fromgroups#!forum/mobile-couchbase)** rather than in Github issues.

# 1. Is This A Duplicate?

It's great if you can scan the open issues to see if your problem/idea has been reported already. If so, feel free to add any new details or just a note that you hit this too. But if you're in a hurry, go ahead and skip this step -- we'd rather get duplicate reports than miss an issue!

# 2. Describe The Bug

## Version

Please indicate **what version of the software** you're using. If you compiled it yourself from source, it helps if you give the Git commit ID, or at least the branch name and date ("I last pulled from master on 6/30.")

If the bug involves replication, also indicate what software and version is on the other end of the line, i.e. "Couchbase Lite Android 1.0" or "Sync Gateway 1.0" or "Sync Gateway commit f3d3229c" or "CouchDB 1.6".

## Include Steps To Reproduce

The most **important information** to provide with a bug report is a clear set of steps to reproduce the problem.  Include as much information as possible that you think may be related to the bug.  An example would be:

* Install & run Sync Gateway 1.0.3 on Mac running OS X 10.10.1
* Install app on iPhone 6 running iOS 8.1.1
* Login with Facebook
* Turn off WiFi
* Add a new document
* Turn on WiFi
* Saw no new documents on Sync Gateway (expected: there should have been some documents)

## Include Actual vs. Expected

As mentioned above, the last thing in your steps to reproduce is the "actual vs expected" behavior.  The reason this is important is because you may have misunderstood what is supposed to happen.  If you give a clear description of what actually happened as well as what you were expecting to happen, it will make the bug a lot easier to figure out.

## General Formatting

Please **format source code or program output (including logs or backtraces) as code**. This makes it easier to read and prevents Github from interpreting any of it as Markdown formatting or bug numbers. To do this, put a line of just three back-quotes ("```") before and after it. (For inline code snippets, just put a single back-quote before and after.)

**If you need to post a block of code/output that is longer than 1/2 a page, please don't paste it into the bug report** -- it's annoying to scroll past. Instead, create a [gist](https://gist.github.com) (or something similar) and just post a link to it.

## Crashes / Exceptions

If the bug causes a crash or an uncaught exception, include a crash log or backtrace. **Please don't add this as a screenshot of the IDE** if you have any alternative. (In Xcode, use the `bt` command in the debugger console to dump a backtrace that you can copy.)

If the log/backtrace is long, don't paste it in directly (see the previous section.)
