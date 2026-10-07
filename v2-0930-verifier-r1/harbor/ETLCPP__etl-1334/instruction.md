Add bounds and empty checks to container classes (#1334)

* add bounds and empty checks to containers

* address code rabbit review

* correct C++11 constexpr error

* rename new constexpr macro and make it global

* rename queue specializations' exceptions

* change front() implementation in locked queue specializations

* refactor usage of CONSTEXPR and NO_EXCEPT

* expand intrusive queue tests

* introduce lock guards on locked queues

* Print test names at test time (#1343)

* revert mutex and return changes on locking queues

* finish reverting the locked queues

---------

Co-authored-by: Roland Reichwein <Roland.Reichwein@bmw.de>
Co-authored-by: John Wellbelove <jwellbelove@users.noreply.github.com>
