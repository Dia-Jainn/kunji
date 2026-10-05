# Air-gapped use: build once, carry the image in, run with --network none for code / image scans.
FROM python:3.12-slim
WORKDIR /opt/kunji
COPY pyproject.toml README.md LICENSE ./
COPY kunji ./kunji
RUN pip install --no-cache-dir . && useradd --create-home scanner
USER scanner
WORKDIR /scan
ENTRYPOINT ["kunji"]
CMD ["--help"]
