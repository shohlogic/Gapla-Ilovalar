import React from "react";

interface BrandMarkIconProps {
  size?: number;
  className?: string;
}

/**
 * Gapla belgisi (src/assets/icon.png): kursor «I» va to'rt ovoz ustuni. Draws in
 * `currentColor` so it follows the foreground treatment of the surface that contains it.
 */
export function BrandMarkIcon({ size = 24, className }: BrandMarkIconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 1024 1024"
      fill="none"
      className={className}
      aria-hidden="true"
    >
      <path d="M195 300H360V355H305V667H360V722H195V667H250V355H195Z" fill="currentColor" />
      <rect x="430" y="449" width="56" height="127" fill="currentColor" />
      <rect x="546" y="389" width="55" height="245" fill="currentColor" />
      <rect x="661" y="389" width="55" height="245" fill="currentColor" />
      <rect x="776" y="449" width="55" height="127" fill="currentColor" />
    </svg>
  );
}
