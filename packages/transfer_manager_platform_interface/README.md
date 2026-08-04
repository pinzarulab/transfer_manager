# transfer_manager_platform_interface

The shared contract implemented by native `transfer_manager` platform
packages. Application code should normally depend on the app-facing package,
not this package directly.

Version 2 adds platform-neutral file/Downloads destinations, completion
notification taps, and artifact open/reveal methods.
