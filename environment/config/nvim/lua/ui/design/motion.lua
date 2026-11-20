local motion = {}

motion.STEP_MS = 100
motion.FRAME_MS = 33
motion.LOOP_STEPS = 24

motion.DURATION = {
  instant = 0,
  fast = 150,
  moderate = 250,
  slow = 450,
  deliberate = 800,
}

motion.EASING = {
  standard = 'out_cubic',
  emphasized = 'in_out',
  linear = 'linear',
}

return motion
