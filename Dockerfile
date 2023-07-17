FROM gcr.io/distroless/python3-debian11

COPY sample.py /
WORKDIR /

CMD ["/sample.py"]
