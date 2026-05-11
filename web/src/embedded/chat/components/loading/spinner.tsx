import './spinner.css';
import type { SVGProps } from 'react';

export const Spinner = (props: SVGProps<SVGSVGElement>) => {
  return (
    <svg
      width="1em"
      height="1em"
      viewBox="0 0 64 64"
      xmlns="http://www.w3.org/2000/svg"
      {...props}
    >
      <g fill="currentColor">
        <rect
          className="bar bar-0"
          x="29"
          y="4"
          width="6"
          height="16"
          rx="3"
          fill="currentColor"
        />
        <rect
          className="bar bar-1"
          x="29"
          y="4"
          width="6"
          height="16"
          rx="3"
          transform="rotate(45 32 32)"
          fill="currentColor"
        />
        <rect
          className="bar bar-2"
          x="29"
          y="4"
          width="6"
          height="16"
          rx="3"
          transform="rotate(90 32 32)"
          fill="currentColor"
        />
        <rect
          className="bar bar-3"
          x="29"
          y="4"
          width="6"
          height="16"
          rx="3"
          transform="rotate(135 32 32)"
          fill="currentColor"
        />
        <rect
          className="bar bar-4"
          x="29"
          y="4"
          width="6"
          height="16"
          rx="3"
          transform="rotate(180 32 32)"
          fill="currentColor"
        />
        <rect
          className="bar bar-5"
          x="29"
          y="4"
          width="6"
          height="16"
          rx="3"
          transform="rotate(225 32 32)"
          fill="currentColor"
        />
        <rect
          className="bar bar-6"
          x="29"
          y="4"
          width="6"
          height="16"
          rx="3"
          transform="rotate(270 32 32)"
          fill="currentColor"
        />
        <rect
          className="bar bar-7"
          x="29"
          y="4"
          width="6"
          height="16"
          rx="3"
          transform="rotate(315 32 32)"
          fill="currentColor"
        />
      </g>
    </svg>
  );
};
