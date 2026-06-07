<?php
/**
 * Plugin Name: SVS Provision Form
 * Description: Renders the one-time token provision form at /provision
 * Version: 1.0.0
 */

if (!defined('ABSPATH')) exit;

final class SVS_Provision_Form {
  const SLUG = 'provision';

  public static function init() {
    add_action('init', [__CLASS__, 'add_rewrite']);
    add_filter('query_vars', [__CLASS__, 'add_query_vars']);
    add_action('template_redirect', [__CLASS__, 'render_page']);
    add_action('wp_enqueue_scripts', [__CLASS__, 'enqueue_assets']);
  }

  public static function add_rewrite() {
    add_rewrite_rule(
      '^' . self::SLUG . '/?$',
      'index.php?svs_provision=1',
      'top'
    );
  }

  public static function add_query_vars($vars) {
    $vars[] = 'svs_provision';
    return $vars;
  }

  public static function enqueue_assets() {
    if (intval(get_query_var('svs_provision')) !== 1) return;

    $base = plugin_dir_url(__FILE__);

    wp_enqueue_style(
      'svs-provision-css',
      $base . 'assets/provision.css',
      [],
      '1.0.0'
    );

    wp_enqueue_script(
      'svs-provision-js',
      $base . 'assets/provision.js',
      [],
      '1.0.0',
      true
    );

    $cfg = [
      'getProvisionLink' =>
        'https://us-central1-svs-app-864ed.cloudfunctions.net/getProvisionLink',
      'submitProvisionForm' =>
        'https://us-central1-svs-app-864ed.cloudfunctions.net/submitProvisionForm',
    ];

    wp_add_inline_script(
      'svs-provision-js',
      'window.SVS_PROVISION_API=' . wp_json_encode($cfg) . ';',
      'before'
    );
  }

  public static function render_page() {
    if (intval(get_query_var('svs_provision')) !== 1) return;

    status_header(200);
    nocache_headers();

    echo '<!doctype html><html lang="de"><head>';
    echo '<meta charset="utf-8">';
    echo '<meta name="viewport" content="width=device-width,initial-scale=1">';
    echo '<title>Vermittlungsprämie – SV Souleiman</title>';
    wp_head();
    echo '</head><body>';
    echo '<div id="svs-provision-root"></div>';
    wp_footer();
    echo '</body></html>';
    exit;
  }
}

SVS_Provision_Form::init();