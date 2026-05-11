import type { CSSProperties } from 'react';
import { createPortal } from 'react-dom';

interface Layer {
  distance: number;
  blur: number;
}

const layers: Layer[] = [
  { distance: 80, blur: 0.5 },
  { distance: 70, blur: 1 },
  { distance: 60, blur: 2 },
  { distance: 50, blur: 4 },
  { distance: 40, blur: 8 },
  { distance: 30, blur: 10 },
  { distance: 0, blur: 32 },
];

interface HeaderMaskProps {
  className?: string;
  layerStep?: number;
  portal?: boolean;
  size: number;
  style?: CSSProperties;
}

function getMaskLayers(layerStep: number) {
  const step = Math.max(1, Math.floor(layerStep));

  if (step === 1) {
    return layers;
  }

  return layers.filter((_, index) => index % step === 0);
}

export const HeaderMask = ({
  className,
  layerStep = 1,
  portal = true,
  size,
  style,
}: HeaderMaskProps) => {
  const mask = (
    <div
      data-ignore-minimap-blur
      data-onboarding-screenshot-ignore
      className={className ?? 'fixed left-0 top-0 w-full z-99999'}
      style={{ height: size * 1.7, top: -size * 0.5, ...style }}
    >
      {getMaskLayers(layerStep).map((layer, index) => (
        <div
          className="absolute left-0 top-0 size-full"
          key={index}
          style={{
            zIndex: index,
            backdropFilter: `blur(${layer.blur}px)`,
            maskImage: `linear-gradient(to bottom, black 0%, #000 ${layer.distance}%, transparent 100%)`,
          }}
        />
      ))}
    </div>
  );

  if (!portal) {
    return mask;
  }

  return createPortal(mask, document.body);
};
