import cv2

cap = cv2.VideoCapture(0)

print(cap.isOpened())

success, frame = cap.read()

print(success)
print(frame is None)

cap.release()