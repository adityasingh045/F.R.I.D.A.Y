import cv2
import mediapipe as mp
import pyautogui
import math
import time

# =========================
# CONFIG
# =========================

CAMERA_WIDTH = 640
CAMERA_HEIGHT = 480

SMOOTHING = 0.20

CLICK_THRESHOLD = 35
RIGHT_CLICK_THRESHOLD = 35
SCROLL_THRESHOLD = 35

DRAG_HOLD_TIME = 0.4

# =========================
# INIT
# =========================

cap = cv2.VideoCapture(0)

cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_WIDTH)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)

screen_w, screen_h = pyautogui.size()

pyautogui.FAILSAFE = False

mp_hands = mp.solutions.hands

hands = mp_hands.Hands(
    max_num_hands=1,
    min_detection_confidence=0.7,
    min_tracking_confidence=0.7
)

# =========================
# STATE
# =========================

prev_x = 0
prev_y = 0

dragging = False

pinch_start = None

last_click = 0
last_right_click = 0
last_scroll = 0

gesture_text = "NONE"

# =========================
# HELPERS
# =========================

def distance(p1x, p1y, p2x, p2y):
    return math.hypot(p2x - p1x, p2y - p1y)

# =========================
# LOOP
# =========================

while True:

    success, frame = cap.read()

    if not success:
        continue

    frame = cv2.flip(frame, 1)

    h, w, _ = frame.shape

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

    results = hands.process(rgb)

    gesture_text = "IDLE"

    if results.multi_hand_landmarks:

        hand = results.multi_hand_landmarks[0]

        landmarks = hand.landmark

        # =========================
        # LANDMARKS
        # =========================

        index_tip = landmarks[8]
        middle_tip = landmarks[12]
        ring_tip = landmarks[16]
        pinky_tip = landmarks[20]

        ix = int(index_tip.x * w)
        iy = int(index_tip.y * h)

        mx = int(middle_tip.x * w)
        my = int(middle_tip.y * h)

        rx = int(ring_tip.x * w)
        ry = int(ring_tip.y * h)

        px = int(pinky_tip.x * w)
        py = int(pinky_tip.y * h)

        # =========================
        # CURSOR CONTROL
        # =========================

        target_x = int(index_tip.x * screen_w)
        target_y = int(index_tip.y * screen_h)

        smooth_x = int(
            SMOOTHING * target_x +
            (1 - SMOOTHING) * prev_x
        )

        smooth_y = int(
            SMOOTHING * target_y +
            (1 - SMOOTHING) * prev_y
        )

        pyautogui.moveTo(smooth_x, smooth_y)

        prev_x = smooth_x
        prev_y = smooth_y

        # =========================
        # DISTANCES
        # =========================

        pinch_distance = distance(
            ix, iy,
            mx, my
        )

        right_distance = distance(
            ix, iy,
            rx, ry
        )

        scroll_distance = distance(
            ix, iy,
            px, py
        )

        now = time.time()

        # =========================
        # LEFT CLICK + DRAG
        # =========================

        if pinch_distance < CLICK_THRESHOLD:

            gesture_text = "PINCH"

            if pinch_start is None:
                pinch_start = now

            hold_time = now - pinch_start

            # HOLD => DRAG

            if hold_time > DRAG_HOLD_TIME:

                if not dragging:

                    pyautogui.mouseDown()

                    dragging = True

                gesture_text = "DRAG"

        else:

            if dragging:

                pyautogui.mouseUp()

                dragging = False

            if pinch_start:

                duration = now - pinch_start

                if duration < DRAG_HOLD_TIME:

                    if now - last_click > 0.4:

                        pyautogui.click()

                        gesture_text = "CLICK"

                        last_click = now

            pinch_start = None

        # =========================
        # RIGHT CLICK
        # =========================

        if right_distance < RIGHT_CLICK_THRESHOLD:

            if now - last_right_click > 0.7:

                pyautogui.rightClick()

                gesture_text = "RIGHT CLICK"

                last_right_click = now

        # =========================
        # SCROLL UP / DOWN
        # =========================

        if scroll_distance < SCROLL_THRESHOLD:

            if now - last_scroll > 0.05:

                movement = prev_y - smooth_y

                if movement > 10:

                    pyautogui.scroll(50)

                    gesture_text = "SCROLL UP"

                elif movement < -10:

                    pyautogui.scroll(-50)

                    gesture_text = "SCROLL DOWN"

                last_scroll = now

        # =========================
        # DRAW LANDMARKS
        # =========================

        mp.solutions.drawing_utils.draw_landmarks(
            frame,
            hand,
            mp_hands.HAND_CONNECTIONS
        )

    # =========================
    # STEP 14 HUD
    # =========================

    cv2.rectangle(
        frame,
        (10, 10),
        (320, 80),
        (0, 0, 0),
        -1
    )

    cv2.putText(
        frame,
        f"Gesture: {gesture_text}",
        (20, 55),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (0, 255, 0),
        2
    )

    cv2.imshow(
        "SpatialOS Gesture Engine",
        frame
    )

    key = cv2.waitKey(1)

    if key == 27:
        break

cap.release()
cv2.destroyAllWindows()