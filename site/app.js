const releaseApi = 'https://api.github.com/repos/leoblanchart92-hub/WORLD-AI/releases/latest';
const fallbackApk = 'https://github.com/leoblanchart92-hub/WORLD-AI/releases/download/v1.7.0/world_ai-1.7.0.apk';

async function syncLatestRelease() {
  const links = [...document.querySelectorAll('[data-apk-download]')];
  const versionLabels = [...document.querySelectorAll('.button-version, .download-version b')];
  try {
    const response = await fetch(releaseApi, {
      headers: { Accept: 'application/vnd.github+json' },
      cache: 'no-store',
    });
    if (!response.ok) throw new Error(`GitHub returned ${response.status}`);

    const release = await response.json();
    const apk = release.assets?.find((asset) => asset.name?.toLowerCase().endsWith('.apk'));
    const url = new URL(apk?.browser_download_url ?? fallbackApk);
    if (url.hostname !== 'github.com' || !url.pathname.endsWith('.apk')) {
      throw new Error('Invalid APK link');
    }

    const version = release.tag_name?.replace(/^v/, '');
    for (const link of links) link.href = url.href;
    if (version) {
      for (const label of versionLabels) label.textContent = `v${version}`;
      const downloadVersion = document.querySelector('.download-version b');
      if (downloadVersion) downloadVersion.textContent = version;
    }
  } catch (error) {
    console.info('La version affichée reste la version publiée connue.', error);
  }
}

document.querySelector('#year').textContent = new Date().getFullYear();
syncLatestRelease();
