FROM tpi-docker-virtual.usw1.packages.broadcom.com/library/ruby:3.2-alpine

RUN apk --no-cache add git make curl jq build-base \
    && git clone https://github.com/cloudfoundry/cf-acceptance-tests \
    --filter=blob:none \
    --depth=1 \
    -b v17.6.0 \
    --single-branch

WORKDIR /cf-acceptance-tests/assets/service_broker
RUN git checkout v17.6.0 \
    && bundle install

EXPOSE 80

ENTRYPOINT ["bundle"]
CMD ["exec", "rackup", "--host", "0.0.0.0"]
