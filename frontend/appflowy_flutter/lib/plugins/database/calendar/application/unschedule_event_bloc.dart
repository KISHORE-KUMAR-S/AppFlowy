import 'package:appflowy/plugins/database/application/cell/cell_cache.dart';
import 'package:appflowy/plugins/database/application/field/field_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../application/database_controller.dart';
import '../../application/row/row_cache.dart';

part 'unschedule_event_bloc.freezed.dart';

class UnscheduleEventsBloc
    extends Bloc<UnscheduleEventsEvent, UnscheduleEventsState> {
  UnscheduleEventsBloc({required this.databaseController})
      : super(UnscheduleEventsState.initial()) {
    _dispatch();
  }

  final DatabaseController databaseController;
  Map<String, FieldInfo> fieldInfoByFieldId = {};

  // Getters
  String get viewId => databaseController.viewId;
  FieldController get fieldController => databaseController.fieldController;
  CellMemCache get cellCache => databaseController.rowCache.cellCache;
  RowCache get rowCache => databaseController.rowCache;

  DatabaseCallbacks? _databaseCallbacks;

  @override
  Future<void> close() async {
    databaseController.removeListener(onDatabaseChanged: _databaseCallbacks);
    _databaseCallbacks = null;
    await super.close();
  }

  void _dispatch() {
    on<UnscheduleEventsEvent>(
      (event, emit) async {
        await event.when(
          initial: () async {
            _startListening();
            _loadAllEvents();
          },
          didLoadAllEvents: (events) {
            emit(
              state.copyWith(
                allEvents: events,
                unscheduleEvents:
                    events.where((element) => !element.hasTimestamp()).toList(),
              ),
            );
          },
          didDeleteEvents: (List<RowId> deletedRowIds) {
            final events = [...state.allEvents];
            events.retainWhere(
              (element) => !deletedRowIds.contains(element.rowMeta.id),
            );
            emit(
              state.copyWith(
                allEvents: events,
                unscheduleEvents:
                    events.where((element) => !element.hasTimestamp()).toList(),
              ),
            );
          },
          didReceiveEvent: (CalendarEventPB event) {
            final events = [...state.allEvents, event];
            emit(
              state.copyWith(
                allEvents: events,
                unscheduleEvents:
                    events.where((element) => !element.hasTimestamp()).toList(),
              ),
            );
          },
        );
      },
    );
  }

  Future<CalendarEventPB?> _loadEvent(
    RowId rowId,
  ) async {
    final payload = DatabaseViewRowIdPB(viewId: viewId, rowId: rowId);
    return DatabaseEventGetCalendarEvent(payload).send().then(
          (result) => result.fold(
            (eventPB) => eventPB,
            (r) {
              Log.error(r);
              return null;
            },
          ),
        );
  }

  void _loadAllEvents() async {
    final payload = CalendarEventRequestPB.create()..viewId = viewId;
    final result = await DatabaseEventGetAllCalendarEvents(payload).send();
    result.fold(
      (events) {
        if (!isClosed) {
          add(UnscheduleEventsEvent.didLoadAllEvents(events.items));
        }
      },
      (r) => Log.error(r),
    );
  }

  void _startListening() {
    _databaseCallbacks = DatabaseCallbacks(
      onRowsCreated: (rows) async {
        if (isClosed) {
          return;
        }
        for (final row in rows) {
          final event = await _loadEvent(row.rowMeta.id);
          if (event != null && !isClosed) {
            add(UnscheduleEventsEvent.didReceiveEvent(event));
          }
        }
      },
      onRowsDeleted: (rowIds) {
        if (isClosed) {
          return;
        }
        add(UnscheduleEventsEvent.didDeleteEvents(rowIds));
      },
      onRowsUpdated: (rowIds, reason) async {
        if (isClosed) {
          return;
        }
        for (final id in rowIds) {
          final event = await _loadEvent(id);
          if (event != null) {
            add(UnscheduleEventsEvent.didDeleteEvents([id]));
            add(UnscheduleEventsEvent.didReceiveEvent(event));
          }
        }
      },
    );

    databaseController.addListener(onDatabaseChanged: _databaseCallbacks);
  }
}

@freezed
class UnscheduleEventsEvent with _$UnscheduleEventsEvent {
  const factory UnscheduleEventsEvent.initial() = _InitialCalendar;

  // Called after loading all the current evnets
  const factory UnscheduleEventsEvent.didLoadAllEvents(
    List<CalendarEventPB> events,
  ) = _ReceiveUnscheduleEventsEvents;

  const factory UnscheduleEventsEvent.didDeleteEvents(List<RowId> rowIds) =
      _DidDeleteEvents;

  const factory UnscheduleEventsEvent.didReceiveEvent(
    CalendarEventPB event,
  ) = _DidReceiveEvent;
}

@freezed
class UnscheduleEventsState with _$UnscheduleEventsState {
  const factory UnscheduleEventsState({
    required DatabasePB? database,
    required List<CalendarEventPB> allEvents,
    required List<CalendarEventPB> unscheduleEvents,
  }) = _UnscheduleEventsState;

  factory UnscheduleEventsState.initial() => const UnscheduleEventsState(
        database: null,
        allEvents: [],
        unscheduleEvents: [],
      );
}
