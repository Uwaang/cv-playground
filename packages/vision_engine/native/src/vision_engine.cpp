#include "vision_engine.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <exception>
#include <sstream>
#include <string>
#include <vector>

#include <opencv2/calib3d.hpp>
#include <opencv2/core.hpp>
#include <opencv2/core/version.hpp>
#include <opencv2/dnn.hpp>
#include <opencv2/features2d.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/objdetect.hpp>
#include <opencv2/objdetect/aruco_detector.hpp>
#include <opencv2/photo.hpp>
#include <opencv2/video/tracking.hpp>

namespace {

int oddKernel(double value, int minimum, int maximum) {
  const int radius = std::clamp(static_cast<int>(std::lround(value)), 0, maximum);
  return std::max(minimum, radius * 2 + 1);
}

void writeMetadata(const std::string& value, char* target, int32_t capacity) {
  if (!target || capacity <= 0) return;
  std::snprintf(target, static_cast<size_t>(capacity), "%s", value.c_str());
}

bool matchOrb(const cv::Mat& a, const cv::Mat& b, int max_matches,
              std::vector<cv::Point2f>& points_a,
              std::vector<cv::Point2f>& points_b) {
  auto orb = cv::ORB::create(800);
  std::vector<cv::KeyPoint> keys_a, keys_b;
  cv::Mat descriptors_a, descriptors_b;
  orb->detectAndCompute(a, cv::noArray(), keys_a, descriptors_a);
  orb->detectAndCompute(b, cv::noArray(), keys_b, descriptors_b);
  if (descriptors_a.empty() || descriptors_b.empty()) return false;
  cv::BFMatcher matcher(cv::NORM_HAMMING, true);
  std::vector<cv::DMatch> matches;
  matcher.match(descriptors_a, descriptors_b, matches);
  std::sort(matches.begin(), matches.end(),
            [](const cv::DMatch& left, const cv::DMatch& right) {
              return left.distance < right.distance;
            });
  for (size_t i = 0; i < matches.size() &&
                     static_cast<int>(i) < max_matches; ++i) {
    const auto& m = matches[i];
    points_a.push_back(keys_a[m.queryIdx].pt);
    points_b.push_back(keys_b[m.trainIdx].pt);
  }
  return !points_a.empty();
}

const char* cocoLabel(int index) {
  static const char* kLabels[] = {
      "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train",
      "truck", "boat", "traffic light", "fire hydrant", "stop sign",
      "parking meter", "bench", "bird", "cat", "dog", "horse", "sheep",
      "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella",
      "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard",
      "sports ball", "kite", "baseball bat", "baseball glove", "skateboard",
      "surfboard", "tennis racket", "bottle", "wine glass", "cup", "fork",
      "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
      "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
      "couch", "potted plant", "bed", "dining table", "toilet", "tv",
      "laptop", "mouse", "remote", "keyboard", "cell phone", "microwave",
      "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase",
      "scissors", "teddy bear", "hair drier", "toothbrush"};
  if (index < 0 || index >= static_cast<int>(sizeof(kLabels) / sizeof(kLabels[0])))
    return "object";
  return kLabels[index];
}

int detectYolo(const cv::Mat& source, cv::Mat& output,
               const char* path, double confidence_percent,
               double nms_percent, std::string& details) {
  if (!path || !path[0]) return -1;
  auto net = cv::dnn::readNetFromONNX(path);
  net.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
  net.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);
  constexpr int kInputSize = 640;
  cv::Mat rgb;
  cv::cvtColor(source, rgb, cv::COLOR_GRAY2BGR);
  auto blob = cv::dnn::blobFromImage(
      rgb, 1.0 / 255.0, cv::Size(kInputSize, kInputSize),
      cv::Scalar(), true, false);
  net.setInput(blob);
  const cv::Mat predictions = net.forward();
  if (predictions.dims != 3 || predictions.type() != CV_32F) return -4;
  const int first = predictions.size[1];
  const int second = predictions.size[2];
  const bool channels_first = first < second;
  const int rows = channels_first ? second : first;
  const int columns = channels_first ? first : second;
  // Supported: standard raw YOLOv8/YOLO11 [1, 4+classes, anchors]
  // and raw YOLOv5 [1, anchors, 5+classes]. Exported NMS outputs differ.
  if (columns < 5 || columns > 100 || rows <= 0 || rows > 100000) return -4;
  const bool has_objectness = columns == 85;
  const int class_start = has_objectness ? 5 : 4;
  auto value = [&](int row, int column) -> float {
    return channels_first
        ? predictions.ptr<float>(0, column)[row]
        : predictions.ptr<float>(0, row)[column];
  };
  const float score_cutoff = std::clamp(static_cast<float>(confidence_percent / 100.0), 0.01f, 0.99f);
  const float nms_cutoff = std::clamp(static_cast<float>(nms_percent / 100.0), 0.01f, 0.99f);
  std::vector<cv::Rect> boxes;
  std::vector<float> scores;
  std::vector<int> classes;
  for (int row = 0; row < rows; ++row) {
    const float obj = has_objectness ? value(row, 4) : 1.0f;
    float best_score = 0.0f;
    int best_class = -1;
    for (int cls = class_start; cls < columns; ++cls) {
      const float score = obj * value(row, cls);
      if (score > best_score) {
        best_score = score;
        best_class = cls - class_start;
      }
    }
    if (best_class < 0 || best_score < score_cutoff) continue;
    const float scale_x = static_cast<float>(source.cols) / kInputSize;
    const float scale_y = static_cast<float>(source.rows) / kInputSize;
    const float cx = value(row, 0) * scale_x;
    const float cy = value(row, 1) * scale_y;
    const float bw = value(row, 2) * scale_x;
    const float bh = value(row, 3) * scale_y;
    if (!std::isfinite(cx) || !std::isfinite(cy) || !std::isfinite(bw) ||
        !std::isfinite(bh) || bw <= 0 || bh <= 0) continue;
    cv::Rect rect(static_cast<int>(cx - bw / 2), static_cast<int>(cy - bh / 2),
                  std::max(1, static_cast<int>(bw)), std::max(1, static_cast<int>(bh)));
    rect &= cv::Rect(0, 0, source.cols, source.rows);
    if (rect.empty()) continue;
    boxes.push_back(rect);
    scores.push_back(best_score);
    classes.push_back(best_class);
  }
  std::vector<int> chosen;
  cv::dnn::NMSBoxes(boxes, scores, score_cutoff, nms_cutoff, chosen);
  std::ostringstream summary;
  summary << chosen.size() << " detections";
  for (size_t i = 0; i < chosen.size() && i < 12; ++i) {
    const int index = chosen[i];
    const char* label = cocoLabel(classes[index]);
    cv::rectangle(output, boxes[index], cv::Scalar(255), 2);
    std::ostringstream caption;
    caption << label << " " << static_cast<int>(scores[index] * 100) << "%";
    cv::putText(output, caption.str(),
                cv::Point(boxes[index].x, std::max(12, boxes[index].y - 4)),
                cv::FONT_HERSHEY_SIMPLEX, 0.45, cv::Scalar(255), 1);
    summary << "; " << caption.str();
  }
  details = summary.str();
  return 0;
}

}  // namespace

extern "C" {

int32_t vision_engine_abi_version(void) { return 1; }

const char* vision_engine_opencv_version(void) { return CV_VERSION; }

int32_t vision_engine_canny_gray(
    const uint8_t* input, int32_t width, int32_t height, int32_t input_stride,
    uint8_t* output, int32_t output_stride,
    double low_threshold, double high_threshold) {
  if (!input || !output || width <= 0 || height <= 0 ||
      input_stride < width || output_stride < width ||
      low_threshold < 0 || high_threshold < low_threshold) return -1;
  try {
    cv::Mat source(height, width, CV_8UC1,
                   const_cast<uint8_t*>(input), input_stride);
    cv::Mat edges;
    cv::Canny(source, edges, low_threshold, high_threshold);
    for (int32_t row = 0; row < height; ++row)
      std::memcpy(output + static_cast<size_t>(row) * output_stride,
                  edges.ptr(row), static_cast<size_t>(width));
    return 0;
  } catch (const cv::Exception&) {
    return -2;
  } catch (const std::exception&) {
    return -3;
  } catch (...) {
    return -3;
  }
}

int32_t vision_engine_process_gray(
    const uint8_t* input, int32_t width, int32_t height, int32_t input_stride,
    const uint8_t* second, int32_t second_stride,
    uint8_t* output, int32_t output_stride,
    int32_t operation, double parameter_a, double parameter_b,
    const char* model_path, char* metadata, int32_t metadata_capacity) {
  if (!input || !output || !metadata || metadata_capacity < 1 ||
      width <= 0 || height <= 0 || width > 4096 || height > 4096 ||
      input_stride < width || output_stride < width ||
      operation < 0 || operation > 36 ||
      !std::isfinite(parameter_a) || !std::isfinite(parameter_b) ||
      (second && second_stride < width)) return -1;
  metadata[0] = '\0';
  if ((operation == 24 || operation == 25 || operation == 28 ||
       operation == 29 || operation == 30 || operation == 32 ||
       operation == 34) && !second) return -1;
  try {
    const cv::Mat image(height, width, CV_8UC1,
                        const_cast<uint8_t*>(input), input_stride);
    const cv::Mat paired = second ?
        cv::Mat(height, width, CV_8UC1, const_cast<uint8_t*>(second), second_stride) :
        cv::Mat();
    cv::Mat result = image.clone();
    std::string info;
    const double a = parameter_a;
    const double b = parameter_b;
    switch (operation) {
      case 0:
        if (a < 0 || b < a) return -1;
        cv::Canny(image, result, a, b);
        break;
      case 1:
        break;
      case 2: {
        const int kernel = oddKernel(a, 3, 20);
        cv::GaussianBlur(image, result, cv::Size(kernel, kernel), 0);
        break;
      }
      case 3: {
        const int kernel = oddKernel(a, 3, 15);
        cv::medianBlur(image, result, kernel);
        break;
      }
      case 4:
        cv::bilateralFilter(image, result, std::max(3, static_cast<int>(a)),
                            std::max(1.0, b), std::max(1.0, b));
        break;
      case 5:
        cv::threshold(image, result, a, 255, cv::THRESH_BINARY);
        break;
      case 6:
        cv::adaptiveThreshold(image, result, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C,
                              cv::THRESH_BINARY, oddKernel(a, 3, 24), b);
        break;
      case 7: {
        cv::Mat gx, gy, abs_x, abs_y;
        cv::Sobel(image, gx, CV_16S, 1, 0);
        cv::Sobel(image, gy, CV_16S, 0, 1);
        cv::convertScaleAbs(gx, abs_x);
        cv::convertScaleAbs(gy, abs_y);
        cv::addWeighted(abs_x, 0.5, abs_y, 0.5, 0, result);
        break;
      }
      case 8: {
        cv::Mat laplacian;
        cv::Laplacian(image, laplacian, CV_16S);
        cv::convertScaleAbs(laplacian, result);
        break;
      }
      case 9:
      case 10:
      case 11:
      case 12: {
        const int radius = std::clamp(static_cast<int>(a), 1, 16);
        const auto element = cv::getStructuringElement(
            cv::MORPH_RECT, cv::Size(radius * 2 + 1, radius * 2 + 1));
        const int morphology = operation == 9 ? cv::MORPH_ERODE :
                               operation == 10 ? cv::MORPH_DILATE :
                               operation == 11 ? cv::MORPH_OPEN : cv::MORPH_CLOSE;
        cv::morphologyEx(image, result, morphology, element);
        break;
      }
      case 13:
        cv::equalizeHist(image, result);
        break;
      case 14:
        cv::createCLAHE(std::max(1.0, a), cv::Size(8, 8))->apply(image, result);
        break;
      case 15: {
        cv::Mat binary;
        cv::threshold(image, binary, a, 255, cv::THRESH_BINARY);
        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(binary, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
        result = cv::Mat::zeros(image.size(), CV_8UC1);
        cv::drawContours(result, contours, -1, cv::Scalar(255), 2);
        info = std::to_string(contours.size()) + " contours";
        break;
      }
      case 16: {
        cv::Mat edges;
        cv::Canny(image, edges, 50, 150);
        std::vector<cv::Vec4i> lines;
        cv::HoughLinesP(edges, lines, 1, CV_PI / 180.0, std::max(1, static_cast<int>(a)), 25, 10);
        for (const auto& line : lines)
          cv::line(result, cv::Point(line[0], line[1]),
                   cv::Point(line[2], line[3]), cv::Scalar(255), 2);
        info = std::to_string(lines.size()) + " line segments";
        break;
      }
      case 17: {
        cv::Mat blurred;
        cv::medianBlur(image, blurred, 5);
        std::vector<cv::Vec3f> circles;
        cv::HoughCircles(blurred, circles, cv::HOUGH_GRADIENT, 1.2,
                         std::max(10.0, image.rows / 12.0), 100, std::max(1.0, a));
        for (const auto& circle : circles)
          cv::circle(result, cv::Point(cvRound(circle[0]), cvRound(circle[1])),
                     cvRound(circle[2]), cv::Scalar(255), 2);
        info = std::to_string(circles.size()) + " circles";
        break;
      }
      case 18: {
        const int channels[] = {0};
        const int hist_size[] = {256};
        const float range[] = {0, 256};
        const float* ranges[] = {range};
        cv::Mat hist;
        cv::calcHist(&image, 1, channels, cv::Mat(), hist, 1, hist_size, ranges);
        cv::normalize(hist, hist, 0, result.rows - 1, cv::NORM_MINMAX);
        result = cv::Mat::zeros(image.size(), CV_8UC1);
        for (int i = 0; i < 256; ++i) {
          const int x = i * result.cols / 256;
          cv::line(result, cv::Point(x, result.rows - 1),
                   cv::Point(x, result.rows - 1 - static_cast<int>(hist.at<float>(i))),
                   cv::Scalar(255), std::max(1, result.cols / 256));
        }
        break;
      }
      case 19: {
        const cv::Mat kernel = (cv::Mat_<float>(3, 3) <<
            0, -1, 0, -1, 5, -1, 0, -1, 0);
        cv::filter2D(image, result, -1, kernel);
        break;
      }
      case 20: {
        const auto matrix = cv::getRotationMatrix2D(
            cv::Point2f(width / 2.f, height / 2.f), a, 1.0);
        cv::warpAffine(image, result, matrix, image.size());
        break;
      }
      case 21: {
        cv::Mat corners, normalized;
        cv::cornerHarris(image, corners, 2, 3, 0.04);
        cv::normalize(corners, normalized, 0, 255, cv::NORM_MINMAX);
        int count = 0;
        for (int y = 0; y < normalized.rows; y += 2)
          for (int x = 0; x < normalized.cols; x += 2)
            if (normalized.at<float>(y, x) > 255 - std::clamp(a, 1.0, 100.0)) {
              cv::circle(result, cv::Point(x, y), 2, cv::Scalar(255), 1);
              ++count;
            }
        info = std::to_string(count) + " corner candidates";
        break;
      }
      case 22: {
        auto orb = cv::ORB::create(std::clamp(static_cast<int>(a), 10, 2000));
        std::vector<cv::KeyPoint> keypoints;
        orb->detect(image, keypoints);
        for (const auto& keypoint : keypoints)
          cv::circle(result, keypoint.pt, 3, cv::Scalar(255), 1);
        info = std::to_string(keypoints.size()) + " ORB features";
        break;
      }
      case 23: {
        cv::QRCodeDetector detector;
        cv::Mat corners;
        info = detector.detectAndDecode(image, corners);
        if (info.empty()) info = "No QR code decoded";
        if (!corners.empty() && corners.total() == 4) {
          const auto* coords = corners.ptr<cv::Point2f>();
          for (int i = 0; i < 4; ++i)
            cv::line(result, coords[i], coords[(i + 1) % 4], cv::Scalar(255), 3);
        }
        break;
      }
      case 24: {
        cv::Mat flow;
        cv::calcOpticalFlowFarneback(image, paired, flow, 0.5, 3, 15, 3, 5, 1.2, 0);
        const int spacing = std::clamp(static_cast<int>(a), 5, 80);
        int count = 0;
        for (int y = spacing / 2; y < height; y += spacing)
          for (int x = spacing / 2; x < width; x += spacing) {
            const auto vector = flow.at<cv::Point2f>(y, x);
            if (cv::norm(vector) < 0.3) continue;
            cv::arrowedLine(result, cv::Point(x, y),
                            cv::Point(cvRound(x + vector.x * 2), cvRound(y + vector.y * 2)),
                            cv::Scalar(255), 1, cv::LINE_AA, 0, 0.3);
            ++count;
          }
        info = std::to_string(count) + " optical-flow vectors";
        break;
      }
      case 25:
        cv::absdiff(image, paired, result);
        cv::threshold(result, result, a, 255, cv::THRESH_BINARY);
        break;
      case 26:
        cv::fastNlMeansDenoising(image, result, std::max(1.f, static_cast<float>(a)), 7, 21);
        break;
      case 27: {
        cv::Mat mask;
        cv::threshold(image, mask, a, 255, cv::THRESH_BINARY);
        cv::inpaint(image, mask, result, 3, cv::INPAINT_TELEA);
        info = "Auto-mask: bright pixels (best for light scratches)";
        break;
      }
      case 28: {
        const int block_size = std::clamp(oddKernel(a / 2.0, 5, 12), 5, 25);
        cv::Mat disparity;
        auto stereo = cv::StereoBM::create(64, block_size);
        stereo->compute(image, paired, disparity);
        disparity.convertTo(result, CV_8U, 255.0 / (64.0 * 16.0));
        info = "Relative disparity; use rectified left/right images";
        break;
      }
      case 29:
      case 30:
      case 34: {
        std::vector<cv::Point2f> a_points, b_points;
        const int limit = operation == 29 ? std::clamp(static_cast<int>(a), 10, 500) : 300;
        matchOrb(image, paired, limit, a_points, b_points);
        if (operation == 29) {
          for (size_t i = 0; i < a_points.size(); ++i) {
            cv::circle(result, a_points[i], 3, cv::Scalar(255), 1);
            cv::line(result, a_points[i], b_points[i], cv::Scalar(255), 1);
          }
          info = std::to_string(a_points.size()) + " matched ORB descriptors";
        } else {
          if (a_points.size() < 4) return -4;
          cv::Mat inlier_mask;
          auto homography = cv::findHomography(b_points, a_points, cv::RANSAC, 4.0, inlier_mask);
          if (homography.empty()) return -4;
          cv::Mat aligned;
          cv::warpPerspective(paired, aligned, homography, image.size());
          if (operation == 30)
            result = aligned;
          else
            cv::addWeighted(image, 0.5, aligned, 0.5, 0, result);
          info = std::to_string(cv::countNonZero(inlier_mask)) + " homography inliers";
          if (operation == 34) info += "; same-size blended crop";
        }
        break;
      }
      case 31: {
        const int status = detectYolo(image, result, model_path, a, b, info);
        if (status != 0) return status;
        break;
      }
      case 32: {
        std::vector<cv::Mat> exposures = {image, paired};
        cv::Mat merged;
        cv::createMergeMertens()->process(exposures, merged);
        merged.convertTo(result, CV_8U, 255);
        info = "Two-image exposure fusion; align images first";
        break;
      }
      case 33: {
        cv::aruco::ArucoDetector detector(
            cv::aruco::getPredefinedDictionary(cv::aruco::DICT_4X4_50));
        std::vector<std::vector<cv::Point2f>> corners;
        std::vector<int> ids;
        detector.detectMarkers(image, corners, ids);
        for (const auto& polygon : corners)
          for (int i = 0; i < 4; ++i)
            cv::line(result, polygon[i], polygon[(i + 1) % 4], cv::Scalar(255), 2);
        info = std::to_string(ids.size()) + " ArUco markers (4x4_50)";
        break;
      }
      case 35: {
        std::vector<cv::Point2f> corners;
        const bool found = cv::findChessboardCorners(image, cv::Size(9, 6), corners);
        cv::drawChessboardCorners(result, cv::Size(9, 6), corners, found);
        info = found ? "9x6 chessboard corners found" : "No 9x6 chessboard found";
        break;
      }
      case 36: {
        const double focal = std::max(width, height);
        const cv::Mat intrinsic = (cv::Mat_<double>(3, 3) <<
            focal, 0, width / 2.0,
            0, focal, height / 2.0,
            0, 0, 1);
        const cv::Mat distortion = (cv::Mat_<double>(1, 5) <<
            -a / 100.0, 0.04, 0, 0, 0);
        cv::undistort(image, result, intrinsic, distortion);
        info = "Illustrative distortion coefficients, not calibrated";
        break;
      }
      default:
        return -1;
    }
    if (result.empty() || result.type() != CV_8UC1 ||
        result.rows != height || result.cols != width) return -4;
    for (int32_t row = 0; row < height; ++row)
      std::memcpy(output + static_cast<size_t>(row) * output_stride,
                  result.ptr(row), static_cast<size_t>(width));
    writeMetadata(info, metadata, metadata_capacity);
    return 0;
  } catch (const cv::Exception&) {
    return -2;
  } catch (const std::exception&) {
    return -3;
  } catch (...) {
    return -3;
  }
}

}  // extern "C"
