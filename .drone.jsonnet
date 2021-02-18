local locale_gen_cmds_default(cmds) = cmds + [
  'echo "en_US.UTF-8 UTF-8" > /etc/locale.gen',
  'locale-gen',
];

local locale_gen_cmds_ubuntu1204(cmds) = cmds + [
  'locale-gen en_US.UTF-8',
];

local test_step(emacs_ver) = {
  name: 'test-emacs%s' % emacs_ver,
  image: 'silex/emacs:%s-ci-cask' % emacs_ver,
  commands: [
    'export PATH=/opt/exodus/bin:$PATH',
    'cask install',
    'sleep 15',
    // Waiting for httpbin
    'cask exec ert-runner',
  ],
  volumes: [
    {
      name: 'locales',
      path: '/usr/lib/locale',
    },
    {
      name: 'exodus',
      path: '/opt/exodus',
    },
  ],
  environment: {
    MB_URL_TEST__HTTPBIN_PREFIX: 'http://httpbin',
  },
  depends_on: [
    'install ci deps',
  ],
};

local generate_pipeline(args) = {
  kind: 'pipeline',
  name: args.pipeline_name,
  services: [
    {
      name: 'httpbin',
      image: 'kennethreitz/httpbin',
    },
  ],
  steps: [
    {
      // Ensure locale exists.
      name: 'install locales',
      image: args.deps_image,
      commands: args.locale_gen_cmds_func([
        'apt-get update',
        'apt-get install --yes locales',
      ]),
      volumes: [
        {
          name: 'locales',
          path: '/usr/lib/locale',
        },
      ],
    },
    {
      name: 'install ci deps',
      image: 'nixos/nix:latest',
      commands: [
        'nix-env -i curl httpie',
        'nix-env -iA nixpkgs.python3Packages.pipx',
        'pipx run --spec exodus-bundler exodus --tarball curl http https | tar x -z -f - -C /opt/exodus --strip-components=1',
      ],
      volumes: [
        {
          name: 'exodus',
          path: '/opt/exodus',
        },
      ],
      depends_on: [
        'install locales',
      ],
    },
  ] + std.map(test_step, args.emacs_vers),
  volumes: [
    {
      name: 'locales',
      temp: {},
    },
    {
      name: 'exodus',
      temp: {},
    },
  ],
};

std.map(generate_pipeline, [
  {
    pipeline_name: 'default',
    deps_image: 'buildpack-deps:stable',
    locale_gen_cmds_func: locale_gen_cmds_default,
    emacs_vers: ['24.5', '25.1', '25.2', '25.3', '26.1', '26.2', '26.3'],
  },
  {
    // According to [1] and [2], Emacs 24.4 cannot be built on Ubuntu 18.04, so
    // `silex/emacs:24.4` use Ubuntu 12.04 as its base image.  We have to
    // install dependencies on Ubuntu 12.04.
    //
    // [1]: https://github.com/Silex/docker-emacs/issues/34
    // [2]: https://github.com/Silex/docker-emacs/commit/df66168dc4edc5a746351685b88ac59d3efcb183
    pipeline_name: 'test for emacs 24.4',
    deps_image: 'ubuntu:12.04',
    locale_gen_cmds_func: locale_gen_cmds_ubuntu1204,
    emacs_vers: ['24.4'],
  },
])
