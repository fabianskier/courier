# Tasks

## 1. Seeding output

- [ ] 1.1 Add the "Try it" examples after the "Send events with" command in `CourierDemo.Seeds.report/2` for `:mix` and `:release` (the first merchant of the data set, Sunrise Bakery, owns the fast `ok` endpoint; the existing "Release output ready to use" scenario forbids `mix ` anywhere in the release output); verify with new tests in `test/courier_demo/seed_examples_test.exs` covering every scenario of `specs/demo-seeds/spec.md`, and `sh .smelt/checks.sh`
