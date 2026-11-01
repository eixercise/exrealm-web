FROM ruby:3.2-slim

RUN apt-get update -qq && apt-get install -y build-essential libsqlite3-dev

WORKDIR /app
COPY Gemfile /app/Gemfile
RUN bundle install

COPY . /app

EXPOSE 7860
CMD ["ruby", "app.rb", "-p", "7860", "-o", "0.0.0.0"]
