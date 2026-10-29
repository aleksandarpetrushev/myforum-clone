import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import {
  CreateEventRequest,
  EventSummary,
  MyRegistrations,
  NotificationItem,
  NotificationPage,
  NotificationPreferences,
  Organization,
  Registration,
  Session,
  Topic,
} from './models';

export const API_URL = 'http://localhost:3000';

@Injectable({ providedIn: 'root' })
export class ForumApi {
  private readonly http = inject(HttpClient);

  login(email: string, password: string): Observable<Session> {
    return this.http.post<Session>(`${API_URL}/api/session`, { email, password });
  }

  events(filters: { q?: string; topicId?: string; location?: string }): Observable<{ data: EventSummary[] }> {
    let params = new HttpParams();
    if (filters.q) params = params.set('q', filters.q);
    if (filters.topicId) params = params.set('topic_id', filters.topicId);
    if (filters.location) params = params.set('location', filters.location);
    return this.http.get<{ data: EventSummary[] }>(`${API_URL}/api/events`, { params });
  }

  event(id: number): Observable<EventSummary> {
    return this.http.get<EventSummary>(`${API_URL}/api/events/${id}`);
  }

  createEvent(body: CreateEventRequest): Observable<EventSummary> {
    return this.http.post<EventSummary>(`${API_URL}/api/events`, { event: body });
  }

  cancelEvent(id: number): Observable<EventSummary> {
    return this.http.post<EventSummary>(`${API_URL}/api/events/${id}/cancel`, {});
  }

  adminOrganizations(): Observable<{ data: Organization[] }> {
    return this.http.get<{ data: Organization[] }>(`${API_URL}/api/me/organizations`);
  }

  organizations(): Observable<{ data: Organization[] }> {
    return this.http.get<{ data: Organization[] }>(`${API_URL}/api/organizations`);
  }

  register(eventId: number): Observable<Registration> {
    return this.http.post<Registration>(`${API_URL}/api/registrations`, { event_id: eventId });
  }

  cancelRegistration(eventId: number): Observable<Registration> {
    return this.http.post<Registration>(`${API_URL}/api/registrations/cancel`, { event_id: eventId });
  }

  topics(): Observable<{ data: Topic[] }> {
    return this.http.get<{ data: Topic[] }>(`${API_URL}/api/topics`);
  }

  follow(topicId: number): Observable<void> {
    return this.http.post<void>(`${API_URL}/api/topics/${topicId}/follow`, {});
  }

  unfollow(topicId: number): Observable<void> {
    return this.http.delete<void>(`${API_URL}/api/topics/${topicId}/follow`);
  }

  registrations(): Observable<MyRegistrations> {
    return this.http.get<MyRegistrations>(`${API_URL}/api/me/registrations`);
  }

  notifications(cursor?: string | null): Observable<NotificationPage> {
    let params = new HttpParams();
    if (cursor) params = params.set('cursor', cursor);
    return this.http.get<NotificationPage>(`${API_URL}/api/me/notifications`, { params });
  }

  markNotificationRead(id: number): Observable<NotificationItem & { unread_count: number }> {
    return this.http.post<NotificationItem & { unread_count: number }>(`${API_URL}/api/me/notifications/${id}/read`, {});
  }

  markAllNotificationsRead(): Observable<{ unread_count: number }> {
    return this.http.post<{ unread_count: number }>(`${API_URL}/api/me/notifications/read_all`, {});
  }

  notificationPreferences(): Observable<NotificationPreferences> {
    return this.http.get<NotificationPreferences>(`${API_URL}/api/me/notification_preferences`);
  }

  updateNotificationPreferences(preferences: NotificationPreferences): Observable<NotificationPreferences> {
    return this.http.patch<NotificationPreferences>(`${API_URL}/api/me/notification_preferences`, {
      notification_preference: preferences,
    });
  }
}
