# Pinned toolchain for `flutter analyze` and `flutter test`: JDK 17, Flutter and
# the Android SDK. The repository is bind-mounted at /workspace, not copied in.
# Flutter matches the version CI uses (.github/workflows/ci.yml): change both together.
FROM eclipse-temurin:17-jdk-noble@sha256:bdd7eeee8f2259194d39a9525f09abfddcb97a7bdc6fcd97de6f83652e80f772

ARG FLUTTER_VERSION=3.47.9
ARG CMDLINE_TOOLS_ZIP=commandlinetools-linux-11076708_latest.zip
ARG CMDLINE_TOOLS_SHA256=2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258
# Flutter's default compileSdk (FlutterExtension.kt in the Flutter SDK).
ARG ANDROID_PLATFORM=36
ARG ANDROID_BUILD_TOOLS=36.0.0

ENV FLUTTER_HOME=/opt/flutter \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    HOME=/home/dev \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    PUB_CACHE=/home/dev/.pub-cache
ENV PATH=$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl unzip xz-utils zip ca-certificates libglu1-mesa libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/* \
    # The container runs as the host user's id, which owns none of /opt.
    && git config --system --add safe.directory '*'

RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && curl -fsSL -o /tmp/cmdline-tools.zip "https://dl.google.com/android/repository/$CMDLINE_TOOLS_ZIP" \
    && echo "$CMDLINE_TOOLS_SHA256  /tmp/cmdline-tools.zip" | sha256sum -c - \
    && unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager "platform-tools" "platforms;android-$ANDROID_PLATFORM" "build-tools;$ANDROID_BUILD_TOOLS"

RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
    && flutter precache --universal \
    && flutter --version

RUN mkdir -p "$HOME/.pub-cache" \
    && chmod -R a+rwX "$FLUTTER_HOME" "$ANDROID_HOME" "$HOME"

WORKDIR /workspace
