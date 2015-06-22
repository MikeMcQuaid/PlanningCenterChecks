# PlanningCenterChecks
PlanningCenterChecks is a simple use of the [Planning Center Online](http://get.planningcenteronline.com) API to query for data that hasn't been input correctly for the music group at my church, [St. Paul's and St. George's, Edinburgh](http://www.pandgchurch.org.uk) (also known as "Ps and Gs").

## Features
- list songs missing attachments (which makes them harder to learn)
- list songs missing Spotify/YouTube media (which makes them harder to practice)
- list songs using DOC(X) attachments (which cannot be used by all apps)
- list songs missing PDF attachments (which can be used by most apps)
- list songs missing OnSong attachments (which is a great app)
- list songs not used in 60 days (so they can be flushed)
- list song arrangements named 'Default Arrangement' (so more detail can be added)
- list people who haven't confirmed service requests (so they can be nagged)
- list people who have declined service requests (so they can be swapped)
- list people without birthdays entered (so they can have :cake:)

## Usage
Open http://psandgs-pco-checks.herokuapp.com/ in your web browser.

Alternatively, to use locally run:
```bash
git clone https://github.com/mikemcquaid/PlanningCenterChecks
cd PlanningCenterChecks
bundle install
PCO_KEY="..." PCO_SECRET="..." foreman start
```

Alternatively, to deploy to [Heroku](https://www.heroku.com) click:

[![Deploy to Heroku](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy)

## Configuration Environment Variables
- `PCO_KEY`: the Planning Center Online API OAuth 1.0a consumer key.
- `PCO_SECRET`: the Planning Center Online API key OAuth 1.0a secret.
- `SESSION_SECRET`: the secret used for cookie session storage.
- `WEB_CONCURRENCY`: the number of Unicorn (web server) processes to run.

## Status
Just the above two methods implemented in the quickest way possible. Might flesh this out and make it more attractive if it becomes useful.

## Contact
[Mike McQuaid](mailto:mike@mikemcquaid.com)

## License
PlanningCenterChecks is licensed under the [MIT License](http://en.wikipedia.org/wiki/MIT_License).
The full license text is available in [LICENSE.txt](https://github.com/mikemcquaid/PlanningCenterChecks/blob/master/LICENSE.txt).
