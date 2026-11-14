/**
 * Gapla ilova belgisi (src/assets/icon.png bilan bir xil): grafit plitka, mandarin «I» kursor, to'rt ovoz ustuni.
 * Gapla G44 (2026-11-12): bu joylarda eski brendning ko'k doira belgisi kodning o'zida chizilgan edi.
 */
export function GaplaAppIcon({ className, label }: { className?: string; label?: string }) {
  return (
    <svg
      viewBox="0 0 1024 1024"
      className={className}
      role={label ? "img" : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      <rect width="1024" height="1024" rx="241" fill="#1C1917" />
      <path d="M195 300H360V355H305V667H360V722H195V667H250V355H195Z" fill="#FF9447" />
      <rect x="430" y="449" width="56" height="127" fill="#F5F5F5" />
      <rect x="546" y="389" width="55" height="245" fill="#F5F5F5" />
      <rect x="661" y="389" width="55" height="245" fill="#F5F5F5" />
      <rect x="776" y="449" width="55" height="127" fill="#F5F5F5" />
    </svg>
  );
}
