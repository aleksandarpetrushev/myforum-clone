import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { EventSummary, NotificationItem, Registration, Session, Topic } from './models';

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

  register(eventId: number): Observable<Registration> {
    return this.http.post<Registration>(`${API_URL}/api/events/${eventId}/register`, {});
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

  registrations(): Observable<{ data: Registration[] }> {
    return this.http.get<{ data: Registration[] }>(`${API_URL}/api/me/registrations`);
  }

  notifications(): Observable<{ data: NotificationItem[] }> {
    return this.http.get<{ data: NotificationItem[] }>(`${API_URL}/api/me/notifications`);
  }
}
