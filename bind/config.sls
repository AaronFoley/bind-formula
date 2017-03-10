{% from "bind/map.jinja" import map with context %}

include:
  - bind

{{ map.log_dir }}:
  file.directory:
    - user: root
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: 775
    - require:
      - pkg: bind

bind_restart:
  service.running:
    - name: {{ map.service }}
    - reload: False
    - watch:
      - file: {{ map.log_dir }}/query.log

{{ map.log_dir }}/query.log:
  file.managed:
    - user: {{ salt['pillar.get']('bind:config:user', map.user) }}
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: {{ salt['pillar.get']('bind:config:log_mode', map.log_mode) }}
    - require:
      - file: {{ map.log_dir }}

named_directory:
  file.directory:
    - name: {{ map.named_directory }}
    - user: {{ salt['pillar.get']('bind:config:user', map.user) }}
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: 775
    - makedirs: True
    - require:
      - pkg: bind

{% if grains['os_family'] == 'RedHat' %}

key_directory:
  file.directory:
    - name: {{ map.key_directory }}
    - user: root
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: 775
    - require:
      - pkg: bind
    - watch_in:
      - service: bind

key_directory_perms:
  cmd.run:
    - cwd: {{ map.key_directory }}
    - name: chmod 644 *.key && chmod 640 *.private && chown root:{{ salt['pillar.get']('bind:config:group', map.group) }} *

zsk_rollover_script:
  file.managed:
    - source: 'salt://bind/files/common/zsk_rollover.sh'
    - name: /usr/local/bin/zsk_rollover.sh
    - user: {{ salt['pillar.get']('bind:config:user', map.user) }}
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: 755
    - template: jinja
    - context:
        map: {{ map }}

{% endif %}

bind_config:
  file.managed:
    - name: {{ map.config }}
    - source: 'salt://{{ map.config_source_dir }}/named.conf'
    - template: jinja
    - user: {{ salt['pillar.get']('bind:config:user', map.user) }}
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: {{ salt['pillar.get']('bind:config:mode', map.mode) }}
    - context:
        map: {{ map }}
    - require:
      - pkg: bind
    - watch_in:
      - service: bind

bind_local_config:
  file.managed:
    - name: {{ map.local_config }}
    - source: 'salt://{{ map.config_source_dir }}/named.conf.local'
    - template: jinja
    - user: {{ salt['pillar.get']('bind:config:user', map.user) }}
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: {{ salt['pillar.get']('bind:config:mode', '644') }}
    - context:
        map: {{ map }}
    - require:
      - pkg: bind
      - file: {{ map.log_dir }}/query.log
    - watch_in:
      - service: bind

{% if grains['os_family'] not in ['Arch', 'FreeBSD']  %}
bind_default_config:
  file.managed:
    - name: {{ map.default_config }}
    - source: salt://{{ map.config_source_dir }}/default
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - watch_in:
      - service: bind_restart
{% endif %}

{% if grains['os_family'] == 'Debian' %}
bind_key_config:
  file.managed:
    - name: {{ map.key_config }}
    - source: 'salt://{{ map.config_source_dir }}/named.conf.key'
    - template: jinja
    - user: {{ salt['pillar.get']('bind:config:user', map.user) }}
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: {{ salt['pillar.get']('bind:config:mode', '644') }}
    - require:
      - pkg: bind
    - watch_in:
      - service: bind

bind_options_config:
  file.managed:
    - name: {{ map.options_config }}
    - source: 'salt://{{ map.config_source_dir }}/named.conf.options'
    - template: jinja
    - user: {{ salt['pillar.get']('bind:config:user', map.user) }}
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: {{ salt['pillar.get']('bind:config:mode', '644') }}
    - require:
      - pkg: bind
    - watch_in:
      - service: bind

bind_default_zones:
  file.managed:
    - name: {{ map.default_zones_config }}
    - source: 'salt://{{ map.config_source_dir }}/named.conf.default-zones'
    - template: jinja
    - user: {{ salt['pillar.get']('bind:config:user', map.user) }}
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: {{ salt['pillar.get']('bind:config:mode', '644') }}
    - require:
      - pkg: bind
    - watch_in:
      - service: bind

/etc/logrotate.d/{{ map.service }}:
  file.managed:
    - source: salt://{{ map.config_source_dir }}/logrotate_bind
    - template: jinja
    - user: root
    - group: root
    - context:
        map: {{ map }}
{% endif %}

{% for zone, zone_data in salt['pillar.get']('bind:configured_zones', {}).items() -%}
{%- set file = salt['pillar.get']("bind:available_zones:" + zone + ":file") %}
{% if file and zone_data['type'] == "master" -%}
zones-{{ zone }}:
  file.managed:
    - name: {{ map.named_directory }}/{{ file }}
    - source: 'salt://{{ map.zones_source_dir }}/{{ file }}'
    - template: jinja
    - user: {{ salt['pillar.get']('bind:config:user', map.user) }}
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: {{ salt['pillar.get']('bind:config:mode', '644') }}
    - watch_in:
      - service: bind
    - require:
      - file: named_directory

{% if zone_data['dnssec'] is defined and zone_data['dnssec'] -%}
signed-{{ zone }}:
  cmd.run:
    - cwd: {{ map.named_directory }}
    - name: zonesigner -zone {{ zone }} {{ file }}
    - prereq:
      - file: zones-{{ zone }}
{% endif %}

{% if zone_data['create-keys'] is defined and zone_data['create-keys'] -%}

{%- set keygen_options = '-a ' + salt['pillar.get']("bind:config:keygen_options:algorithm","RSASHA256") %}
{%- set keygen_options = '-b ' + salt['pillar.get']("bind:config:keygen_options:size","2048") %}
{%- set keygen_options = keygen_options + ' -r ' + salt['pillar.get']("bind:config:keygen_options:randomdev","/dev/random") %}
{% if salt['pillar.get']("bind:config:keygen_options:nsec3",False) %}
{%- set keygen_options = keygen_options + ' -3 ' %}
{% endif %}

{{zone}}-ksk:
  cmd.run:
    - cwd: {{ map.key_directory }}
    - name: dnssec-keygen {{ keygen_options }} -fk {{zone}}
    - unless: cat {{ map.key_directory }}/K{{zone}}*.key | grep 'key-signing key' > /dev/null
    - require:
      - file: key_directory
    - watch_in:
      - service: bind_restart
      - file: key_directory_perms

{{zone}}-zsk:
  cmd.run:
    - cwd: {{ map.key_directory }}
    - name: dnssec-keygen {{ keygen_options }} {{zone}}
    - unless: cat {{ map.key_directory }}/K{{zone}}*.key | grep 'zone-signing key' > /dev/null
    - require:
      - file: key_directory
    - watch_in:
      - service: bind_restart
      - file: key_directory_perms
{% endif %}

{% if zone_data['enable-nsec3'] is defined and zone_data['enable-nsec3'] -%}

{{zone}}-nsec3:
  cmd.run:
    - name: rndc signing -nsec3param {{ zone_data['nsec-options'] }} {{ salt['random.get_str'](16) }} {{zone}}
    - unless: named-compilezone -D -f raw -o - {{ map.named_directory }}/{{ file }} {{ map.named_directory }}/{{ file }}.signed
    - require:
      - file: key_directory
    - prereq:
      - service: bind

{% endif %}

{% if zone_data['zsk-rollover'] is defined and zone_data['zsk-rollover']['enabled'] -%}

{{zone}}-zsk-rollover:
  cron.present:
    - identifier: {{zone}}-zsk-rollover
    - name: /usr/local/bin/zsk_rollover.sh {{zone}} {{ zone_data['zsk-rollover']['inactive'] }} {{ zone_data['zsk-rollover']['deleted'] }}
    - user: {{ salt['pillar.get']('bind:config:user', map.user) }}
    {% if zone_data['zsk-rollover']['minute'] is defined %}
    - minute: "{{ zone_data['zsk-rollover']['minute'] }}"
    {% endif %}
    {% if zone_data['zsk-rollover']['hour'] is defined %}
    - hour: "{{ zone_data['zsk-rollover']['hour'] }}"
    {% endif %}
    {% if zone_data['zsk-rollover']['daymonth'] is defined %}
    - daymonth: "{{ zone_data['zsk-rollover']['daymonth'] }}"
    {% endif %}
    {% if zone_data['zsk-rollover']['month'] is defined %}
    - month: "{{ zone_data['zsk-rollover']['month'] }}"
    {% endif %}
    {% if zone_data['zsk-rollover']['dayweek'] is defined %}
    - dayweek: "{{ zone_data['zsk-rollover']['dayweek'] }}"
    {% endif %}
    - require:
      - file: zsk_rollover_script

{% endif %}

{% endif %}
{% endfor %}

{%- for view, view_data in salt['pillar.get']('bind:configured_views', {}).items() %}
{% for zone, zone_data in view_data.get('configured_zones', {}).items() -%}
{%- set file = salt['pillar.get']("bind:available_zones:" + zone + ":file") %}
{% if file and zone_data['type'] == "master" -%}
zones-{{ view }}-{{ zone }}:
  file.managed:
    - name: {{ map.named_directory }}/{{ file }}
    - source: 'salt://{{ map.zones_source_dir }}/{{ file }}'
    - template: jinja
    - user: {{ salt['pillar.get']('bind:config:user', map.user) }}
    - group: {{ salt['pillar.get']('bind:config:group', map.group) }}
    - mode: {{ salt['pillar.get']('bind:config:mode', '644') }}
    - watch_in:
      - service: bind
    - require:
      - file: named_directory

{% if zone_data['dnssec'] is defined and zone_data['dnssec'] -%}
signed-{{ view }}-{{ zone }}:
  cmd.run:
    - cwd: {{ map.named_directory }}
    - name: zonesigner -zone {{ zone }} {{ file }}
    - prereq:
      - file: zones-{{ view }}-{{ zone }}
{% endif %}

{% endif %}
{% endfor %}
{% endfor %}
