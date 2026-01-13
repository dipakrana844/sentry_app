import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/offline/offline_queue.dart';
import '../../core/sentry/sentry_config.dart';

/// Multi-step form screen for creating task reports.
/// 
/// **Sentry integration:**
/// - Tracks each step completion as breadcrumb
/// - Monitors form validation errors
/// - Captures upload failures
/// - Tracks form submission performance
/// 
/// **Real-world problem solved:**
/// Complex forms are easier to complete when broken into steps. This also
/// allows tracking where users drop off and what validation errors occur.
class FormScreen extends StatefulWidget {
  const FormScreen({super.key});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  int _currentStep = 0;
  final PageController _pageController = PageController();

  // Step 1: Basic Info
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _step1Key = GlobalKey<FormState>();

  // Step 2: Details
  DateTime? _selectedDate;
  String? _location;
  String? _priority;
  final _step2Key = GlobalKey<FormState>();

  // Step 3: Review & Upload
  XFile? _selectedImage;
  double _uploadProgress = 0.0;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // Start screen load transaction
    final transaction = SentryConfig.startScreenTransaction('form_screen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SentryConfig.finishScreenTransaction(transaction);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_step1Key.currentState!.validate()) {
        _step1Key.currentState!.save();
        SentryConfig.addBreadcrumb(
          'Form step 1 completed: Basic Info',
          category: 'form',
          data: {
            'title': _titleController.text,
            'description_length': _descriptionController.text.length,
          },
        );
        _goToStep(1);
      } else {
        SentryConfig.addBreadcrumb(
          'Form step 1 validation failed',
          category: 'validation',
          level: SentryLevel.warning,
        );
      }
    } else if (_currentStep == 1) {
      if (_step2Key.currentState!.validate()) {
        _step2Key.currentState!.save();
        SentryConfig.addBreadcrumb(
          'Form step 2 completed: Details',
          category: 'form',
          data: {
            'date': _selectedDate?.toIso8601String(),
            'location': _location,
            'priority': _priority,
          },
        );
        _goToStep(2);
      } else {
        SentryConfig.addBreadcrumb(
          'Form step 2 validation failed',
          category: 'validation',
          level: SentryLevel.warning,
        );
      }
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      SentryConfig.addBreadcrumb(
        'Form step ${_currentStep + 1} - going back to step $_currentStep',
        category: 'form',
      );
      _goToStep(_currentStep - 1);
    }
  }

  void _goToStep(int step) {
    setState(() {
      _currentStep = step;
    });
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = image;
        });

        SentryConfig.addBreadcrumb(
          'Image selected for upload',
          category: 'form',
          data: {
            'image_name': image.name,
            'image_size': await image.length(),
          },
        );
      }
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'pick_image'}),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _simulateUpload() async {
    if (_selectedImage == null) {
      SentryConfig.addBreadcrumb(
        'Upload attempted without image',
        category: 'form',
        level: SentryLevel.warning,
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    final uploadSpan = SentryConfig.startCustomSpan(
      'file_upload',
      'Uploading image: ${_selectedImage!.name}',
    );

    try {
      // Simulate upload progress
      for (int i = 0; i <= 100; i += 10) {
        await Future.delayed(const Duration(milliseconds: 200));
        setState(() {
          _uploadProgress = i / 100;
        });
      }

      // Simulate upload failure (20% chance)
      if (DateTime.now().millisecond % 5 == 0) {
        throw Exception('File Upload Failed: Connection Reset');
      }

      SentryConfig.finishCustomSpan(uploadSpan, status: const SpanStatus.ok());
      SentryConfig.addBreadcrumb(
        'Image upload completed successfully',
        category: 'network',
        data: {'image_name': _selectedImage!.name},
      );

      setState(() {
        _isUploading = false;
        _uploadProgress = 1.0;
      });
    } catch (e, stack) {
      SentryConfig.finishCustomSpan(
        uploadSpan,
        status: const SpanStatus.internalError(),
      );
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({
          'operation': 'file_upload',
          'image_name': _selectedImage!.name,
        }),
      );

      setState(() {
        _isUploading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload failed. Error sent to Sentry.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _submitForm() async {
    if (_selectedDate == null) {
      SentryConfig.addBreadcrumb(
        'Form submission attempted with null date',
        category: 'validation',
        level: SentryLevel.error,
      );
      SentryConfig.captureException(
        Exception('Form submission failed: Date is required'),
        hint: Hint.withMap({'operation': 'form_submission'}),
      );
      return;
    }

    final submitTransaction = SentryConfig.startCustomSpan(
      'form_submission',
      'Submitting task report form',
    );

    try {
      SentryConfig.addBreadcrumb(
        'Form submission started',
        category: 'user.action',
        data: {
          'title': _titleController.text,
          'date': _selectedDate!.toIso8601String(),
          'location': _location,
          'priority': _priority,
          'has_image': _selectedImage != null,
        },
      );

      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));

      // Add to offline queue (simulating offline action)
      await OfflineQueue.addAction('create_task', {
        'title': _titleController.text,
        'description': _descriptionController.text,
        'date': _selectedDate!.toIso8601String(),
        'location': _location,
        'priority': _priority,
        'has_image': _selectedImage != null,
      });

      SentryConfig.finishCustomSpan(
        submitTransaction,
        status: const SpanStatus.ok(),
      );

      SentryConfig.addBreadcrumb(
        'Form submitted successfully',
        category: 'user.action',
        level: SentryLevel.info,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task report submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Reset form
        _resetForm();
      }
    } catch (e, stack) {
      SentryConfig.finishCustomSpan(
        submitTransaction,
        status: const SpanStatus.internalError(),
      );
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'form_submission'}),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submission failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _resetForm() {
    setState(() {
      _currentStep = 0;
      _titleController.clear();
      _descriptionController.clear();
      _selectedDate = null;
      _location = null;
      _priority = null;
      _selectedImage = null;
      _uploadProgress = 0.0;
    });
    _pageController.jumpToPage(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Task Report'),
        actions: [
          if (_currentStep > 0)
            TextButton(
              onPressed: _resetForm,
              child: const Text('Reset'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Step indicator
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _buildStepIndicator(0, 'Basic Info'),
                _buildStepConnector(),
                _buildStepIndicator(1, 'Details'),
                _buildStepConnector(),
                _buildStepIndicator(2, 'Review'),
              ],
            ),
          ),

          // Form content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep1(),
                _buildStep2(),
                _buildStep3(),
              ],
            ),
          ),

          // Navigation buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentStep > 0)
                  OutlinedButton(
                    onPressed: _previousStep,
                    child: const Text('Previous'),
                  )
                else
                  const SizedBox.shrink(),
                ElevatedButton(
                  onPressed: _currentStep < 2 ? _nextStep : _submitForm,
                  child: Text(_currentStep < 2 ? 'Next' : 'Submit'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive || isCompleted
                  ? Colors.blueAccent
                  : Colors.grey[300],
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                  : Text(
                      '${step + 1}',
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.grey[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive || isCompleted
                  ? Colors.blueAccent
                  : Colors.grey[600],
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepConnector() {
    return Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 20),
      color: Colors.grey[300],
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _step1Key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Task Title *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  SentryConfig.addBreadcrumb(
                    'Title validation failed: empty',
                    category: 'validation',
                    level: SentryLevel.warning,
                  );
                  return 'Please enter a task title';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 5,
              validator: (value) {
                if (value != null && value.length > 1000) {
                  SentryConfig.addBreadcrumb(
                    'Description validation failed: too long',
                    category: 'validation',
                    level: SentryLevel.warning,
                  );
                  return 'Description must be less than 1000 characters';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _step2Key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Date picker
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );

                if (date != null) {
                  setState(() {
                    _selectedDate = date;
                  });
                  SentryConfig.addBreadcrumb(
                    'Date selected: ${date.toIso8601String()}',
                    category: 'form',
                  );
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  _selectedDate != null
                      ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
                      : 'Select a date',
                  style: TextStyle(
                    color: _selectedDate != null
                        ? Colors.black
                        : Colors.grey[600],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Location
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Location',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
              onSaved: (value) => _location = value,
            ),
            const SizedBox(height: 16),

            // Priority dropdown
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.flag),
              ),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
              ],
              onChanged: (value) {
                setState(() {
                  _priority = value;
                });
                SentryConfig.addBreadcrumb(
                  'Priority selected: $value',
                  category: 'form',
                );
              },
              onSaved: (value) => _priority = value,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Review & Upload',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Review summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Title: ${_titleController.text}'),
                  const SizedBox(height: 8),
                  Text('Date: ${_selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : 'Not set'}'),
                  const SizedBox(height: 8),
                  Text('Location: ${_location ?? 'Not set'}'),
                  const SizedBox(height: 8),
                  Text('Priority: ${_priority ?? 'Not set'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Image picker
          const Text(
            'Attach Image (Optional)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image),
                label: const Text('Pick Image'),
              ),
              const SizedBox(width: 16),
              if (_selectedImage != null)
                Expanded(
                  child: Text(
                    _selectedImage!.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),

          if (_selectedImage != null) ...[
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.file(
                File(_selectedImage!.path),
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isUploading ? null : _simulateUpload,
              child: _isUploading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text('Uploading ${(_uploadProgress * 100).toInt()}%'),
                      ],
                    )
                  : const Text('Upload Image'),
            ),
            if (_uploadProgress > 0 && !_isUploading)
              LinearProgressIndicator(value: _uploadProgress),
          ],

          const SizedBox(height: 32),

          // Debug actions
          if (const bool.fromEnvironment('dart.vm.product') == false) ...[
            const Divider(),
            const Text(
              'Debug Actions',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () {
                // Simulate null date error
                setState(() {
                  _selectedDate = null;
                });
                _submitForm();
              },
              child: const Text('Test: Submit with Null Date'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                throw Exception('Intentional Crash: Form Screen Exception');
              },
              child: const Text('TRIGGER CRASH'),
            ),
          ],
        ],
      ),
    );
  }
}
