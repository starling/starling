FROM alpine:3.6 as dev
ENV BUNDLE_SILENCE_ROOT_WARNING=1
RUN apk add --no-cache \
  build-base \
  ruby \
  ruby-dev \
  ruby-bundler \
  bash \
  git
WORKDIR /app
COPY . .
RUN bundle install && rake build

FROM alpine:3.6 as build
RUN apk add --no-cache \
  build-base \
  ruby \
  ruby-dev
COPY --from=dev /app/pkg/*.gem .
RUN gem install --no-doc *.gem

FROM alpine:3.6
COPY --from=build /usr/lib/ruby/gems/ /usr/lib/ruby/gems/
RUN apk add --no-cache \
  libgcc \
  libstdc++ \
  musl \
  ruby \
  ruby-libs \
 && ruby -e "Gem::Specification.map.each do |spec| \
   Gem::Installer.for_spec( \
     spec, \
     wrappers: true, \
     force: true, \
     install_dir: spec.base_dir, \
     build_args: spec.build_args, \
   ).generate_bin \
  end"
EXPOSE 22122
ENTRYPOINT ["/usr/bin/starling"]
