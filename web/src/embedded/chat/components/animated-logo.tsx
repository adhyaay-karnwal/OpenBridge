import { type SVGProps, useEffect, useRef, useState } from 'react';
import { animate as animejsAnimate, spring } from 'animejs';
import { cn } from '@/utils/cn';

const animate = (...props: Parameters<typeof animejsAnimate>) => {
  const instance = animejsAnimate(...props);
  const promise = new Promise(resolve => {
    instance.onComplete = resolve;
  });
  return { instance, promise };
};

export interface AnimatedLogoProps {
  animation?: boolean;
  loop?: boolean;
  loopDuration?: number;
}

const offset = {
  idle: 1,
  enter: -26,
  exit: -175,
};
const length = {
  idle: 0,
  enter: 136,
  exit: 0,
};

class AnimationController {
  private abortController: AbortController | null = null;

  // enter animation config
  private enterDrawDelay = 0;
  private enterMoveDelay = 0;
  private enterDrawDuration = 1000;
  private enterMoveDuration = 800;

  // exit animation config
  private exitDrawDelay = 0;
  private exitMoveDelay = 0;
  private exitDrawDuration = 600;
  private exitMoveDuration = 600;

  constructor(
    public path: SVGPathElement,
    public loop: boolean,
    public loopDuration: number = 1000
  ) {}

  async start() {
    this.abortController = new AbortController();
    // apply enter animation
    await this.animateEnter();

    // if not looping, exit
    if (this.abortController?.signal.aborted) return;
    if (!this.loop) return;

    // will loop, wait for a while to display full icon
    await this.wait();

    // apply exit animation
    if (this.abortController?.signal.aborted) return;
    await this.animateExit();

    // wait for loop duration to replay
    await this.wait(this.loopDuration);

    // replay
    if (this.abortController?.signal.aborted) return;
    await this.start();
  }

  async animateEnter() {
    // Control line length
    const drawAnim = animate(this.path, {
      strokeDasharray: [`${length.idle} 1000`, `${length.enter} 1000`],
      delay: this.enterDrawDelay,
      ease: spring({
        duration: this.enterDrawDuration,
        bounce: 0.2,
      }),
    });
    // Control line offset
    const moveAnim = animate(this.path, {
      strokeDashoffset: [`${offset.idle}`, `${offset.enter}`],
      delay: this.enterMoveDelay,
      ease: spring({
        duration: this.enterMoveDuration,
        bounce: 0.4,
      }),
    });
    this.abortController?.signal.addEventListener(
      'abort',
      () => {
        drawAnim.instance.cancel();
        moveAnim.instance.cancel();
      },
      { once: true }
    );
    await Promise.all([drawAnim.promise, moveAnim.promise]);
  }

  wait(duration = 1000) {
    return new Promise(resolve => setTimeout(resolve, duration));
  }

  async animateExit() {
    const drawAnim = animate(this.path, {
      strokeDasharray: `${length.exit} 1000`,
      delay: this.exitDrawDelay,
      duration: this.exitDrawDuration,
    });
    const moveAnim = animate(this.path, {
      strokeDashoffset: `${offset.exit}`,
      delay: this.exitMoveDelay,
      duration: this.exitMoveDuration,
    });
    this.abortController?.signal.addEventListener(
      'abort',
      () => {
        drawAnim.instance.cancel();
        moveAnim.instance.cancel();
      },
      { once: true }
    );
    await Promise.all([drawAnim.promise, moveAnim.promise]);
  }

  stop() {
    this.abortController?.abort();
  }
}

export const AnimatedLogo = ({
  animation = true,
  loop = true,
  loopDuration = 1000,
  strokeWidth = 4,
  ...svgProps
}: AnimatedLogoProps &
  Omit<SVGProps<SVGSVGElement>, 'children' | 'viewBox'>) => {
  const pathRef = useRef<SVGPathElement>(null);

  useEffect(() => {
    const path = pathRef.current;
    if (!path) return;

    if (!animation) {
      // show icon without animation
      path.setAttribute('stroke-dasharray', `${length.enter} 1000`);
      path.setAttribute('stroke-dashoffset', `${offset.enter}`);
      return;
    }

    const controller = new AnimationController(path, loop, loopDuration);
    controller.start();

    return () => {
      controller.stop();
    };
  }, [animation, loop, loopDuration]);

  return (
    <svg
      viewBox="0 0 60 42"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      {...svgProps}
    >
      <path
        ref={pathRef}
        d="M2 38.0024C20 39.5024 18.5001 27.0024 17.8751 23.5757C17.2501 20.1489 16.3751 15.5759 19.3751 9.57581C22.3751 3.57569 26.8752 1.57601 29.8751 2.07601C32.8749 2.57601 34.3751 5.57569 32.8751 10.0757C31.3751 14.5757 24.6318 18.401 24.3751 18.5757C24.1184 18.7504 32.8751 14.504 37.8751 18.0757C41.9723 21.0024 40.5002 25.0024 40.0001 27.0024C39.5 29.0024 37.2562 32.6549 33.5001 35.0024C29.744 37.35 19.8183 41.5024 18.0001 36.5024C16.1819 31.5024 25.5001 27.0024 32.0001 26.5024C38.5001 26.0024 42.2497 26.1489 46.3748 30.0757C50.5 34.0024 47.3748 38.0024 45.5 39.5024"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth={strokeWidth}
        strokeDasharray={`${length.idle} 1000`}
        strokeDashoffset={offset.idle}
      />
    </svg>
  );
};

export const HoverableAnimatedLogo = ({
  appearDelay,
  enterAnimation,
  className,
  ...svgProps
}: Pick<AnimatedLogoProps, 'loopDuration'> &
  Omit<SVGProps<SVGSVGElement>, 'children' | 'viewBox'> & {
    enterAnimation?: boolean;
    appearDelay?: number;
  }) => {
  const [animate, setAnimate] = useState(false);
  const [applyEnterAnimation, setApplyEnterAnimation] =
    useState(enterAnimation);
  const [appear, setAppear] = useState(appearDelay ? false : true);

  useEffect(() => {
    if (appearDelay) {
      setTimeout(() => setAppear(true), appearDelay);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div
      onMouseEnter={() => {
        setApplyEnterAnimation(false);
        setAnimate(true);
      }}
      onMouseLeave={() => setAnimate(false)}
    >
      {appear && (
        <AnimatedLogo
          className={cn('absolute', className)}
          key={animate ? 'animating' : 'static'}
          animation={applyEnterAnimation || animate}
          loop={!applyEnterAnimation}
          {...svgProps}
        />
      )}
      {/* A static placeholder to avoid layout shift */}
      <svg
        viewBox="0 0 60 42"
        xmlns="http://www.w3.org/2000/svg"
        className={cn('opacity-0', className)}
        {...svgProps}
      />
    </div>
  );
};
