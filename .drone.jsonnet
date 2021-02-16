local locale_gen_cmds_default(cmds) = cmds + [
  'echo "en_US.UTF-8 UTF-8" > /etc/locale.gen',
  'locale-gen',
];

local locale_gen_cmds_ubuntu1204(cmds) = cmds + [
  'locale-gen en_US.UTF-8',
];

local linuxbrew_debian_cmds(cmds) = [
  'apt-get update',
  'apt-get install --yes build-essential curl file git',
] + cmds;

local test_step(emacs_ver) = {
  name: 'test-emacs%s' % emacs_ver,
  image: 'silex/emacs:%s-ci-cask' % emacs_ver,
  commands: [
    'echo "/nix/var/nix/profiles/per-user/nixuser/profile"',
    'echo "$HOME/.nix-profile"',
    'ln -sf "/nix/var/nix/profiles/per-user/nixuser/profile" "$HOME/.nix-profile"',
    '. "$HOME/.nix-profile/etc/profile.d/nix.sh"',
    'unset NIX_REMOTE',
    'nix-shell shell.nix',
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
      name: 'nix',
      path: '/nix',
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
      name: 'install nix',
      image: args.deps_image,
      commands: [
        'apt-get update',
        'apt-get install --yes curl sudo',
        'groupadd nixbld',
        'useradd --create-home --groups nixbld nixuser',
        'chown nixuser: /nix',
        'echo "nixuser ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/nixuser',
        'unset NIX_REMOTE',
        'curl -L https://nixos.org/nix/install | sh -s -- --no-daemon',
        '. $HOME/.nix-profile/etc/profile.d/nix.sh',
        'cat $HOME/.nix-profile/etc/profile.d/nix.sh',
        'echo $HOME',
        'echo $PATH',
        'nix-channel --update',
        'nix-env -i nix curl',
      ],
      volumes: [
        {
          name: 'nix',
          path: '/nix',
        },
      ],
      depends_on: [
        'install locales',
      ],
    },
    {
      name: 'install ci deps',
      image: args.deps_image,
      commands: [
        'ls /nix/var/nix/profiles/',
        'ls /nix/var/nix/profiles/per-user/',
        '{ find /nix/var/nix/profiles/ | grep profile.d ; } || true',
        'find /nix/var/nix/profiles/',
        'echo "/nix/var/nix/profiles/per-user/nixuser/profile"',
        'echo "$HOME/.nix-profile"',
        'ln -sf "/nix/var/nix/profiles/per-user/nixuser/profile" "$HOME/.nix-profile"',
        '. "$HOME/.nix-profile/etc/profile.d/nix.sh"',
        'unset NIX_REMOTE',
        'nix-shell --run true shell.nix',
      ],
      volumes: [
        {
          name: 'nix',
          path: '/nix',
        },
      ],
      depends_on: [
        'install nix',
      ],
    },
  ] + std.map(test_step, args.emacs_vers),
  volumes: [
    {
      name: 'locales',
      temp: {},
    },
    {
      name: 'nix',
      temp: {},
    },
  ],
};

std.map(generate_pipeline, [
  {
    pipeline_name: 'default',
    deps_image: 'buildpack-deps:stable',
    linuxbrew_image: 'buildpack-deps:stable',
    locale_gen_cmds_func: locale_gen_cmds_default,
    ci_deps_cmds_func: std.prune,
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
    linuxbrew_image: 'ubuntu:12.04',
    locale_gen_cmds_func: locale_gen_cmds_ubuntu1204,
    ci_deps_cmds_func: linuxbrew_debian_cmds,
    emacs_vers: ['24.4'],
  },
])
